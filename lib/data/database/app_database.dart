import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drift/native.dart';

/// Drift-managed SQLite connection. The small schema is written explicitly in
/// SQL so the database does not depend on generated query classes.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() =>
      AppDatabase(driftDatabase(name: 'abacus_master'));

  /// Isolated in-memory SQLite instance for tests and short-lived operations.
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 3;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await _createProfileTables();
      await _createPracticeTables();
    },
    onUpgrade: (migrator, from, to) async {
      for (var version = from; version < to; version++) {
        switch (version) {
          case 1:
            // Create the original v2 session schema; the following migration
            // step adds the feedback column to both tables exactly once.
            await _createPracticeTables(includeFeedbackMode: false);
          case 2:
            await _upgradeToVersion3();
          default:
            throw StateError(
              'No database migration is registered from v$version to '
              'v${version + 1}.',
            );
        }
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createProfileTables() async {
    await customStatement('''
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
    await customStatement('''
      CREATE TABLE user_settings (
        user_id TEXT NOT NULL PRIMARY KEY
          REFERENCES user_profiles(id) ON DELETE CASCADE,
        difficulty TEXT NOT NULL
          CHECK (difficulty IN ('beginner', 'medium', 'advanced')),
        decimal_precision INTEGER NOT NULL
          CHECK (decimal_precision BETWEEN 0 AND 3),
        answer_feedback_mode TEXT NOT NULL DEFAULT 'immediate'
          CHECK (answer_feedback_mode IN ('immediate', 'endOfTest'))
      )
    ''');
  }

  Future<void> _createPracticeTables({bool includeFeedbackMode = true}) async {
    final sessionFeedbackColumn = includeFeedbackMode
        ? "answer_feedback_mode TEXT NOT NULL DEFAULT 'immediate' "
              "CHECK (answer_feedback_mode IN ('immediate', 'endOfTest')),"
        : '';
    // Profile deletion follows the existing settings policy: local practice
    // history is private to a profile and cascades with that profile.
    await customStatement('''
      CREATE TABLE practice_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL
          REFERENCES user_profiles(id) ON DELETE CASCADE,
        difficulty TEXT NOT NULL
          CHECK (difficulty IN ('beginner', 'medium', 'advanced')),
        question_count INTEGER NOT NULL CHECK (question_count BETWEEN 1 AND 1000),
        duration_us INTEGER NOT NULL CHECK (duration_us > 0),
        operations TEXT NOT NULL CHECK (length(operations) > 0),
        decimal_probability TEXT NOT NULL,
        allowed_decimal_places TEXT NOT NULL,
        allow_mixed_operations INTEGER NOT NULL
          CHECK (allow_mixed_operations IN (0, 1)),
        mixed_operation_probability TEXT NOT NULL,
        $sessionFeedbackColumn
        started_at_us INTEGER NOT NULL,
        ended_at_us INTEGER,
        status TEXT NOT NULL CHECK
          (status IN ('running', 'paused', 'completed', 'cancelled')),
        elapsed_time_us INTEGER NOT NULL DEFAULT 0
          CHECK (elapsed_time_us >= 0 AND elapsed_time_us <= duration_us),
        total_paused_time_us INTEGER NOT NULL DEFAULT 0
          CHECK (total_paused_time_us >= 0),
        paused_at_us INTEGER,
        attempt_count INTEGER NOT NULL DEFAULT 0
          CHECK (attempt_count BETWEEN 0 AND question_count),
        completion_reason TEXT,
        CHECK (
          (status IN ('running', 'paused') AND ended_at_us IS NULL) OR
          (status IN ('completed', 'cancelled') AND ended_at_us IS NOT NULL)
        ),
        CHECK ((status = 'paused' AND paused_at_us IS NOT NULL) OR
          (status != 'paused' AND paused_at_us IS NULL)),
        CHECK ((status IN ('completed', 'cancelled') AND
          completion_reason IS NOT NULL) OR
          (status IN ('running', 'paused') AND completion_reason IS NULL))
      )
    ''');
    await customStatement('''
      CREATE TABLE practice_question_attempts (
        session_id TEXT NOT NULL REFERENCES practice_sessions(id) ON DELETE CASCADE,
        sequence_number INTEGER NOT NULL CHECK (sequence_number > 0),
        expression TEXT NOT NULL CHECK (length(expression) > 0),
        operation TEXT NOT NULL
          CHECK (operation IN ('addition', 'subtraction', 'multiplication', 'division')),
        difficulty TEXT NOT NULL
          CHECK (difficulty IN ('beginner', 'medium', 'advanced')),
        correct_numerator TEXT NOT NULL CHECK (length(correct_numerator) > 0),
        correct_denominator TEXT NOT NULL
          CHECK (length(correct_denominator) > 0 AND correct_denominator != '0'),
        selected_numerator TEXT NOT NULL CHECK (length(selected_numerator) > 0),
        selected_denominator TEXT NOT NULL
          CHECK (length(selected_denominator) > 0 AND selected_denominator != '0'),
        is_correct INTEGER NOT NULL CHECK (is_correct IN (0, 1)),
        response_time_us INTEGER NOT NULL CHECK (response_time_us >= 0),
        answered_at_us INTEGER NOT NULL,
        PRIMARY KEY (session_id, sequence_number)
      )
    ''');
    await customStatement(
      'CREATE INDEX practice_sessions_user_status_ended '
      'ON practice_sessions (user_id, status, ended_at_us DESC)',
    );
    await customStatement(
      'CREATE INDEX practice_sessions_status_started '
      'ON practice_sessions (status, started_at_us)',
    );
    await customStatement(
      'CREATE INDEX practice_attempts_session_sequence '
      'ON practice_question_attempts (session_id, sequence_number)',
    );
  }

  Future<void> _upgradeToVersion3() async {
    // Existing profiles and sessions retain their data; the new preference
    // defaults to immediate feedback for every existing row.
    await customStatement('''
      ALTER TABLE user_settings ADD COLUMN answer_feedback_mode TEXT NOT NULL
        DEFAULT 'immediate'
        CHECK (answer_feedback_mode IN ('immediate', 'endOfTest'))
    ''');
    await customStatement('''
      ALTER TABLE practice_sessions ADD COLUMN answer_feedback_mode TEXT NOT NULL
        DEFAULT 'immediate'
        CHECK (answer_feedback_mode IN ('immediate', 'endOfTest'))
    ''');
  }
}
