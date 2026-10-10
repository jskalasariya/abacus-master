import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:uuid/uuid.dart';

import '../../domain/arithmetic/arithmetic_operation.dart';
import '../../domain/answer_feedback_mode.dart';
import '../../domain/profiles/profile_repository.dart';
import '../../domain/profiles/profile_input_rules.dart';
import '../../domain/profiles/user_profile.dart';
import '../database/app_database.dart';
import '../security/argon2_password_hasher.dart';

/// SQLite-backed profile repository. The domain interface contains no Drift
/// types, and plaintext passwords are only accepted long enough to hash them.
final class SqliteProfileRepository implements ProfileRepository {
  SqliteProfileRepository(
    this._database, {
    PasswordHasher? passwordHasher,
    DateTime Function()? clock,
    Uuid? uuid,
  }) : _passwordHasher = passwordHasher ?? Argon2PasswordHasher(),
       _clock = clock ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final PasswordHasher _passwordHasher;
  final DateTime Function() _clock;
  final Uuid _uuid;

  @override
  Future<UserProfile> createProfile({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = _normalizeAndValidateUsername(username);
    _validatePassword(password);
    final now = _clock().toUtc();
    final id = _uuid.v4();
    final settings = UserSettings(userId: id);
    final passwordHash = await _passwordHasher.hash(password);
    try {
      await _database.transaction(() async {
        await _database.customStatement(
          'INSERT INTO user_profiles '
          '(id, username, password_hash, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?)',
          [
            id,
            normalizedUsername,
            passwordHash,
            now.millisecondsSinceEpoch,
            now.millisecondsSinceEpoch,
          ],
        );
        await _database.customStatement(
          'INSERT INTO user_settings '
          '(user_id, difficulty, decimal_precision, answer_feedback_mode) '
          'VALUES (?, ?, ?, ?)',
          [
            id,
            settings.difficulty.name,
            settings.decimalPrecision,
            settings.answerFeedbackMode.name,
          ],
        );
      });
    } on SqliteException catch (error) {
      throw _translateStorageError(error, normalizedUsername);
    }
    return UserProfile(
      id: id,
      username: normalizedUsername,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<UserProfile?> getProfileById(String id) async {
    final row = await _database
        .customSelect(
          'SELECT id, username, created_at, updated_at '
          'FROM user_profiles WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row == null ? null : _profileFromRow(row);
  }

  @override
  Future<UserProfile?> getProfileByUsername(String username) async {
    final normalizedUsername = _normalizeAndValidateUsername(username);
    final row = await _database
        .customSelect(
          'SELECT id, username, created_at, updated_at '
          'FROM user_profiles WHERE username = ?',
          variables: [Variable.withString(normalizedUsername)],
        )
        .getSingleOrNull();
    return row == null ? null : _profileFromRow(row);
  }

  @override
  Future<List<UserProfile>> getAllProfiles() async {
    final rows = await _database
        .customSelect(
          'SELECT id, username, created_at, updated_at '
          'FROM user_profiles ORDER BY username COLLATE NOCASE',
        )
        .get();
    return rows.map(_profileFromRow).toList(growable: false);
  }

  @override
  Future<UserProfile?> verifyCredentials({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = _normalizeAndValidateUsername(username);
    final row = await _database
        .customSelect(
          'SELECT id, username, password_hash, created_at, updated_at '
          'FROM user_profiles WHERE username = ?',
          variables: [Variable.withString(normalizedUsername)],
        )
        .getSingleOrNull();
    if (row == null) return null;

    final matches = await _passwordHasher.verify(
      password,
      row.read<String>('password_hash'),
    );
    return matches ? _profileFromRow(row) : null;
  }

  @override
  Future<UserSettings?> getSettings(String userId) async {
    final row = await _database
        .customSelect(
          'SELECT user_id, difficulty, decimal_precision, answer_feedback_mode '
          'FROM user_settings WHERE user_id = ?',
          variables: [Variable.withString(userId)],
        )
        .getSingleOrNull();
    return row == null ? null : _settingsFromRow(row);
  }

  @override
  Future<UserProfile> updateProfile({
    required String id,
    String? username,
    String? newPassword,
  }) async {
    if (username == null && newPassword == null) {
      throw const InvalidProfileDataException(
        'Provide a new username or password to update a profile.',
      );
    }
    final normalizedUsername = username == null
        ? null
        : _normalizeAndValidateUsername(username);
    if (newPassword != null) _validatePassword(newPassword);

    final oldProfile = await getProfileById(id);
    if (oldProfile == null) {
      throw ProfileNotFoundException('No profile exists with ID $id.');
    }
    final now = _clock().toUtc();
    final updatedAt = now.isBefore(oldProfile.createdAt)
        ? oldProfile.createdAt
        : now;
    final passwordHash = newPassword == null
        ? null
        : await _passwordHasher.hash(newPassword);

    try {
      final assignments = <String>['updated_at = ?'];
      final variables = <Object?>[updatedAt.millisecondsSinceEpoch];
      if (normalizedUsername != null) {
        assignments.add('username = ?');
        variables.add(normalizedUsername);
      }
      if (passwordHash != null) {
        assignments.add('password_hash = ?');
        variables.add(passwordHash);
      }
      variables.add(id);
      final sql = StringBuffer('UPDATE user_profiles SET ')
        ..write(assignments.join(', '))
        ..write(' WHERE id = ?');
      await _database.customStatement(sql.toString(), variables);
    } on SqliteException catch (error) {
      throw _translateStorageError(error, normalizedUsername);
    }
    return UserProfile(
      id: oldProfile.id,
      username: normalizedUsername ?? oldProfile.username,
      createdAt: oldProfile.createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> changePassword({
    required String id,
    required String currentPassword,
    required String newPassword,
  }) async {
    _validatePassword(newPassword);
    try {
      await _database.transaction(() async {
        final row = await _database
            .customSelect(
              'SELECT password_hash FROM user_profiles WHERE id = ?',
              variables: [Variable.withString(id)],
            )
            .getSingleOrNull();
        if (row == null) {
          throw ProfileNotFoundException('No profile exists with ID $id.');
        }

        final currentHash = row.read<String>('password_hash');
        if (!await _passwordHasher.verify(currentPassword, currentHash)) {
          throw const IncorrectCurrentPasswordException();
        }

        // The existing hasher generates a fresh cryptographic salt for every
        // hash. A compare-and-update guards against a concurrent password
        // change while Argon2id is computing the replacement hash.
        final newHash = await _passwordHasher.hash(newPassword);
        final updated = await _database.customUpdate(
          'UPDATE user_profiles SET password_hash = ? '
          'WHERE id = ? AND password_hash = ?',
          variables: [
            Variable.withString(newHash),
            Variable.withString(id),
            Variable.withString(currentHash),
          ],
        );
        if (updated != 1) {
          throw const ProfileStorageException(
            'The password could not be updated. Please try again.',
          );
        }
      });
    } on SqliteException {
      throw const ProfileStorageException(
        'The password could not be updated because local storage failed.',
      );
    }
  }

  @override
  Future<UserSettings> updateSettings(UserSettings settings) async {
    _validateSettings(settings);
    if (await getProfileById(settings.userId) == null) {
      throw ProfileNotFoundException(
        'No profile exists with ID ${settings.userId}.',
      );
    }
    await _database.customStatement(
      'INSERT INTO user_settings '
      '(user_id, difficulty, decimal_precision, answer_feedback_mode) '
      'VALUES (?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET '
      'difficulty = excluded.difficulty, '
      'decimal_precision = excluded.decimal_precision, '
      'answer_feedback_mode = excluded.answer_feedback_mode',
      [
        settings.userId,
        settings.difficulty.name,
        settings.decimalPrecision,
        settings.answerFeedbackMode.name,
      ],
    );
    return settings;
  }

  @override
  Future<bool> deleteProfile(String id) async {
    final deleted = await _database.customUpdate(
      'DELETE FROM user_profiles WHERE id = ?',
      variables: [Variable.withString(id)],
    );
    return deleted > 0;
  }

  UserProfile _profileFromRow(QueryRow row) => UserProfile(
    id: row.read<String>('id'),
    username: row.read<String>('username'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at'),
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('updated_at'),
      isUtc: true,
    ),
  );

  UserSettings _settingsFromRow(QueryRow row) => UserSettings(
    userId: row.read<String>('user_id'),
    difficulty: ArithmeticDifficulty.values.byName(
      row.read<String>('difficulty'),
    ),
    decimalPrecision: row.read<int>('decimal_precision'),
    answerFeedbackMode: AnswerFeedbackMode.values.byName(
      row.read<String>('answer_feedback_mode'),
    ),
  );

  String _normalizeAndValidateUsername(String username) {
    final normalized = ProfileInputRules.normalizeUsername(username);
    if (normalized == null) {
      throw const InvalidProfileDataException(
        'Username must be 3-24 ASCII letters, numbers, or underscores.',
      );
    }
    return normalized;
  }

  void _validatePassword(String password) {
    if (!ProfileInputRules.isValidPassword(password)) {
      throw const InvalidProfileDataException(
        'Password must contain between 8 and 128 characters.',
      );
    }
  }

  void _validateSettings(UserSettings settings) {
    if (settings.decimalPrecision < 0 || settings.decimalPrecision > 3) {
      throw const InvalidProfileDataException(
        'Decimal precision must be between 0 and 3.',
      );
    }
  }

  ProfileRepositoryException _translateStorageError(
    SqliteException error,
    String? username,
  ) {
    // SQLite extended result code SQLITE_CONSTRAINT_UNIQUE.
    if (error.extendedResultCode == 2067) {
      final userLabel = username == null ? 'Username' : 'Username "$username"';
      return DuplicateUsernameException('$userLabel is already in use.');
    }
    return const ProfileStorageException(
      'The profile could not be saved because local database storage failed.',
    );
  }
}
