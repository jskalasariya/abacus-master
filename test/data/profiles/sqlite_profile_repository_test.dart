import 'package:abacus_master/data/database/app_database.dart';
import 'package:abacus_master/data/profiles/sqlite_profile_repository.dart';
import 'package:abacus_master/data/security/argon2_password_hasher.dart';
import 'package:abacus_master/data/sessions/sqlite_practice_session_repository.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_operation.dart';
import 'package:abacus_master/domain/answer_feedback_mode.dart';
import 'package:abacus_master/domain/profiles/profile_repository.dart';
import 'package:abacus_master/domain/profiles/user_profile.dart';
import 'package:abacus_master/domain/sessions/practice_session.dart';
import 'package:abacus_master/domain/sessions/session_configuration.dart';
import 'package:abacus_master/domain/sessions/session_models.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

void main() {
  late AppDatabase database;
  late SqliteProfileRepository repository;
  var now = DateTime.utc(2026, 1, 2, 3, 4, 5);

  setUp(() {
    database = AppDatabase.inMemory();
    repository = SqliteProfileRepository(
      database,
      passwordHasher: _TestPasswordHasher(),
      clock: () => now,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('initializes versioned schema and enables foreign keys', () async {
    expect(database.schemaVersion, 3);
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      3,
    );
    expect(
      (await database.customSelect('PRAGMA foreign_keys').getSingle())
          .read<int>('foreign_keys'),
      1,
    );

    final tables = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('user_profiles', 'user_settings', 'practice_sessions', "
          "'practice_question_attempts')",
        )
        .get();
    expect(tables.map((row) => row.read<String>('name')).toSet(), {
      'user_profiles',
      'user_settings',
      'practice_sessions',
      'practice_question_attempts',
    });
  });

  test(
    'migrates the existing v1 profile schema without losing profiles',
    () async {
      await database.close();
      const timestamp = 1767323045000;
      database = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('''
              CREATE TABLE user_profiles (
                id TEXT NOT NULL PRIMARY KEY,
                username TEXT NOT NULL UNIQUE
                  CHECK (length(username) BETWEEN 3 AND 24
                    AND username NOT GLOB '*[^a-z0-9_]*'),
                password_hash TEXT NOT NULL CHECK (length(password_hash) > 0),
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL CHECK (updated_at >= created_at)
              )
            ''');
            raw.execute('''
              CREATE TABLE user_settings (
                user_id TEXT NOT NULL PRIMARY KEY
                  REFERENCES user_profiles(id) ON DELETE CASCADE,
                difficulty TEXT NOT NULL
                  CHECK (difficulty IN ('beginner', 'medium', 'advanced')),
                decimal_precision INTEGER NOT NULL
                  CHECK (decimal_precision BETWEEN 0 AND 3)
              )
            ''');
            raw.execute('INSERT INTO user_profiles VALUES (?, ?, ?, ?, ?)', [
              'old-profile',
              'old_user',
              'legacy-hash',
              timestamp,
              timestamp,
            ]);
            raw.execute('INSERT INTO user_settings VALUES (?, ?, ?)', [
              'old-profile',
              'medium',
              2,
            ]);
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      repository = SqliteProfileRepository(
        database,
        passwordHasher: _TestPasswordHasher(),
        clock: () => now,
      );

      final profile = await repository.getProfileById('old-profile');
      expect(profile, isNotNull);
      expect(profile!.username, 'old_user');
      expect(
        await repository.getSettings('old-profile'),
        UserSettings(
          userId: 'old-profile',
          difficulty: ArithmeticDifficulty.medium,
          decimalPrecision: 2,
        ),
      );
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        3,
      );
      final migratedTables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('practice_sessions', 'practice_question_attempts')",
          )
          .get();
      expect(migratedTables.map((row) => row.read<String>('name')).toSet(), {
        'practice_sessions',
        'practice_question_attempts',
      });
    },
  );

  test('creates and retrieves a normalized profile with defaults', () async {
    final profile = await repository.createProfile(
      username: '  MiXeD_Name  ',
      password: 'secure passphrase',
    );

    expect(profile.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(profile.username, 'mixed_name');
    expect(profile.createdAt, now);
    expect(profile.updatedAt, now);
    expect(await repository.getProfileById(profile.id), profile);
    expect(await repository.getProfileByUsername(' MIXED_NAME '), profile);
    expect(
      await repository.getSettings(profile.id),
      UserSettings(userId: profile.id),
    );
  });

  test('normalizes names and prevents duplicate usernames', () async {
    await repository.createProfile(
      username: 'Player_One',
      password: 'secure passphrase',
    );

    await expectLater(
      repository.createProfile(
        username: ' player_one ',
        password: 'another secure password',
      ),
      throwsA(isA<DuplicateUsernameException>()),
    );
  });

  test('updates profile data and timestamp', () async {
    final created = await repository.createProfile(
      username: 'first_user',
      password: 'secure passphrase',
    );
    now = now.add(const Duration(minutes: 1));

    final updated = await repository.updateProfile(
      id: created.id,
      username: 'Second_User',
      newPassword: 'new secure password',
    );

    expect(updated.username, 'second_user');
    expect(updated.createdAt, created.createdAt);
    expect(updated.updatedAt, now);
    expect(await repository.getProfileById(created.id), updated);
  });

  test(
    'changes only the target password after verifying the old one',
    () async {
      final first = await repository.createProfile(
        username: 'password_owner',
        password: 'first passphrase',
      );
      final second = await repository.createProfile(
        username: 'other_owner',
        password: 'other passphrase',
      );
      final savedSettings = UserSettings(
        userId: first.id,
        difficulty: ArithmeticDifficulty.advanced,
        decimalPrecision: 3,
        answerFeedbackMode: AnswerFeedbackMode.endOfTest,
      );
      await repository.updateSettings(savedSettings);
      final sessions = SqlitePracticeSessionRepository(
        database,
        clock: () => now,
      );
      final savedSession = await sessions.createSession(
        userId: first.id,
        configuration: SessionConfiguration(questionCount: 1),
        startedAt: now,
      );
      await sessions.updateLifecycle(
        sessionId: savedSession.id,
        userId: first.id,
        update: SessionLifecycleUpdate(
          state: SessionLifecycleState.completed,
          changedAt: now.add(const Duration(seconds: 2)),
          elapsedTime: const Duration(seconds: 2),
          totalPausedTime: Duration.zero,
          endReason: SessionEndReason.manuallyCompleted,
        ),
      );

      await expectLater(
        repository.changePassword(
          id: first.id,
          currentPassword: 'wrong passphrase',
          newPassword: 'new secure passphrase',
        ),
        throwsA(isA<IncorrectCurrentPasswordException>()),
      );
      await expectLater(
        repository.changePassword(
          id: first.id,
          currentPassword: 'first passphrase',
          newPassword: 'short',
        ),
        throwsA(isA<InvalidProfileDataException>()),
      );

      await repository.changePassword(
        id: first.id,
        currentPassword: 'first passphrase',
        newPassword: 'new secure passphrase',
      );

      expect(
        await repository.verifyCredentials(
          username: first.username,
          password: 'first passphrase',
        ),
        isNull,
      );
      expect(
        await repository.verifyCredentials(
          username: first.username,
          password: 'new secure passphrase',
        ),
        first,
      );
      expect(
        await repository.verifyCredentials(
          username: second.username,
          password: 'other passphrase',
        ),
        second,
      );
      expect(await repository.getProfileById(first.id), first);
      expect(await repository.getSettings(first.id), savedSettings);
      expect(
        await repository.getSettings(second.id),
        UserSettings(userId: second.id),
      );
      expect(
        await sessions.getSession(sessionId: savedSession.id, userId: first.id),
        isNotNull,
      );
    },
  );

  test('does not report success when the password update fails', () async {
    final profile = await repository.createProfile(
      username: 'storage_failure',
      password: 'first passphrase',
    );
    await database.customStatement('''
      CREATE TRIGGER fail_password_change
      BEFORE UPDATE OF password_hash ON user_profiles
      BEGIN SELECT RAISE(ABORT, 'forced test failure'); END
    ''');

    await expectLater(
      repository.changePassword(
        id: profile.id,
        currentPassword: 'first passphrase',
        newPassword: 'new secure passphrase',
      ),
      throwsA(isA<ProfileStorageException>()),
    );
    expect(
      await repository.verifyCredentials(
        username: profile.username,
        password: 'first passphrase',
      ),
      profile,
    );
    expect(
      await repository.verifyCredentials(
        username: profile.username,
        password: 'new secure passphrase',
      ),
      isNull,
    );
  });

  test('prevents changing a profile to another username', () async {
    await repository.createProfile(
      username: 'first_user',
      password: 'secure passphrase',
    );
    final second = await repository.createProfile(
      username: 'second_user',
      password: 'another secure password',
    );

    await expectLater(
      repository.updateProfile(id: second.id, username: ' FIRST_USER '),
      throwsA(isA<DuplicateUsernameException>()),
    );
  });

  test('deletes profiles and cascades settings', () async {
    final profile = await repository.createProfile(
      username: 'delete_me',
      password: 'secure passphrase',
    );

    expect(await repository.deleteProfile(profile.id), isTrue);
    expect(await repository.deleteProfile(profile.id), isFalse);
    expect(await repository.getProfileById(profile.id), isNull);
    expect(await repository.getSettings(profile.id), isNull);
  });

  test('rejects invalid usernames, passwords, and empty updates', () async {
    for (final username in ['', 'ab', 'has spaces', 'non_ascii_é']) {
      await expectLater(
        repository.createProfile(
          username: username,
          password: 'secure passphrase',
        ),
        throwsA(isA<InvalidProfileDataException>()),
      );
    }
    for (final password in ['', 'short', List.filled(129, 'x').join()]) {
      await expectLater(
        repository.createProfile(username: 'valid_name', password: password),
        throwsA(isA<InvalidProfileDataException>()),
      );
    }
    await expectLater(
      repository.updateProfile(id: 'missing'),
      throwsA(isA<InvalidProfileDataException>()),
    );
  });

  test('rejects settings for missing profiles', () async {
    await expectLater(
      repository.updateSettings(const UserSettings(userId: 'missing')),
      throwsA(isA<ProfileNotFoundException>()),
    );
  });

  test('keeps settings isolated per profile', () async {
    final first = await repository.createProfile(
      username: 'first_user',
      password: 'secure passphrase',
    );
    final second = await repository.createProfile(
      username: 'second_user',
      password: 'another secure password',
    );
    final firstSettings = UserSettings(
      userId: first.id,
      difficulty: ArithmeticDifficulty.medium,
      decimalPrecision: 2,
      answerFeedbackMode: AnswerFeedbackMode.endOfTest,
    );
    await repository.updateSettings(firstSettings);
    final secondSettings = UserSettings(
      userId: second.id,
      answerFeedbackMode: AnswerFeedbackMode.immediate,
    );
    await repository.updateSettings(secondSettings);
    expect(await repository.getSettings(first.id), firstSettings);
    expect(await repository.getSettings(second.id), secondSettings);
    await repository.updateSettings(
      secondSettings.copyWith(answerFeedbackMode: AnswerFeedbackMode.endOfTest),
    );
    expect(await repository.getSettings(first.id), firstSettings);
    expect(
      (await repository.getSettings(second.id))!.answerFeedbackMode,
      AnswerFeedbackMode.endOfTest,
    );
  });

  test(
    'v2 migration defaults feedback and preserves profile practice history',
    () async {
      await database.close();
      database = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('''
            CREATE TABLE user_profiles (
              id TEXT PRIMARY KEY, username TEXT, password_hash TEXT,
              created_at INTEGER, updated_at INTEGER
            )
          ''');
            raw.execute('''
            CREATE TABLE user_settings (
              user_id TEXT PRIMARY KEY, difficulty TEXT,
              decimal_precision INTEGER
            )
          ''');
            raw.execute('''
            CREATE TABLE practice_sessions (
              id TEXT PRIMARY KEY, user_id TEXT, status TEXT
            )
          ''');
            raw.execute('''
            CREATE TABLE practice_question_attempts (
              session_id TEXT, sequence_number INTEGER, expression TEXT
            )
          ''');
            raw.execute('INSERT INTO user_profiles VALUES (?, ?, ?, ?, ?)', [
              'legacy',
              'legacy_user',
              'hash',
              10,
              10,
            ]);
            raw.execute('INSERT INTO user_settings VALUES (?, ?, ?)', [
              'legacy',
              'medium',
              2,
            ]);
            raw.execute('INSERT INTO practice_sessions VALUES (?, ?, ?)', [
              'old-session',
              'legacy',
              'completed',
            ]);
            raw.execute(
              'INSERT INTO practice_question_attempts VALUES (?, ?, ?)',
              ['old-session', 1, '2 + 2'],
            );
            raw.execute('PRAGMA user_version = 2');
          },
        ),
      );
      repository = SqliteProfileRepository(
        database,
        passwordHasher: _TestPasswordHasher(),
        clock: () => now,
      );

      final settings = await repository.getSettings('legacy');
      expect(settings!.difficulty, ArithmeticDifficulty.medium);
      expect(settings.decimalPrecision, 2);
      expect(settings.answerFeedbackMode, AnswerFeedbackMode.immediate);
      expect(
        (await database
                .customSelect(
                  'SELECT answer_feedback_mode FROM practice_sessions WHERE id = ?',
                  variables: [Variable.withString('old-session')],
                )
                .getSingle())
            .read<String>('answer_feedback_mode'),
        'immediate',
      );
      expect(
        (await database
                .customSelect(
                  'SELECT COUNT(*) AS count FROM practice_question_attempts',
                )
                .getSingle())
            .read<int>('count'),
        1,
      );
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        3,
      );
    },
  );

  test(
    'enforces SQLite username, foreign-key, and settings constraints',
    () async {
      final profile = await repository.createProfile(
        username: 'constraint_user',
        password: 'secure passphrase',
      );
      final timestamp = now.millisecondsSinceEpoch;

      await expectLater(
        database.customStatement(
          'INSERT INTO user_profiles '
          '(id, username, password_hash, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?)',
          ['another-id', profile.username, 'hash', timestamp, timestamp],
        ),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        database.customStatement(
          'INSERT INTO user_settings (user_id, difficulty, decimal_precision) '
          "VALUES ('missing-user', 'beginner', 0)",
        ),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        database.customStatement(
          'UPDATE user_settings SET decimal_precision = 4 WHERE user_id = ?',
          [profile.id],
        ),
        throwsA(isA<SqliteException>()),
      );
    },
  );

  test(
    'stores a salted Argon2id string rather than the plaintext password',
    () async {
      const password = 'correct horse battery staple';
      final profile = await SqliteProfileRepository(
        database,
        clock: () => now,
      ).createProfile(username: 'secure_user', password: password);

      final row = await database
          .customSelect(
            'SELECT password_hash FROM user_profiles WHERE id = ?',
            variables: [Variable.withString(profile.id)],
          )
          .getSingle();
      final storedHash = row.read<String>('password_hash');
      expect(storedHash, startsWith('argon2id\$v=19\$m=19456,t=2,p=1\$'));
      expect(storedHash, isNot(password));
      expect(storedHash, isNot(contains(password)));
    },
  );
}

final class _TestPasswordHasher implements PasswordHasher {
  @override
  Future<String> hash(String password) async => 'test-only-hash-$password';

  @override
  Future<bool> verify(String password, String encodedHash) async =>
      encodedHash == await hash(password);
}
