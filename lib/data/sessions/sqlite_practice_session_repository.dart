import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:uuid/uuid.dart';

import '../../domain/arithmetic/arithmetic_operation.dart';
import '../../domain/arithmetic/rational.dart';
import '../../domain/answer_feedback_mode.dart';
import '../../domain/sessions/practice_session.dart';
import '../../domain/sessions/practice_session_repository.dart';
import '../../domain/sessions/session_configuration.dart';
import '../../domain/sessions/session_models.dart';
import '../../domain/sessions/practice_history_models.dart';
import '../database/app_database.dart';

/// Drift/SQLite implementation. Rational numerators and denominators are
/// stored as decimal strings, so large BigInt values never pass through REAL.
final class SqlitePracticeSessionRepository
    implements PracticeSessionRepository {
  SqlitePracticeSessionRepository(
    this._database, {
    DateTime Function()? clock,
    Uuid? uuid,
  }) : _clock = clock ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final DateTime Function() _clock;
  final Uuid _uuid;

  @override
  Future<PersistedPracticeSession> createSession({
    required String userId,
    required SessionConfiguration configuration,
    required DateTime startedAt,
  }) async {
    if (userId.trim().isEmpty) {
      throw const InvalidSessionDataException('A session owner is required.');
    }
    final id = _uuid.v4();
    final timestamp = _toMicros(startedAt);
    try {
      await _database.transaction(() async {
        await _database.customStatement(
          'INSERT INTO practice_sessions '
          '(id, user_id, difficulty, question_count, duration_us, operations, '
          'decimal_probability, allowed_decimal_places, allow_mixed_operations, '
          'mixed_operation_probability, answer_feedback_mode, started_at_us, status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ',
          [
            id,
            userId,
            configuration.difficulty.name,
            configuration.questionCount,
            configuration.duration.inMicroseconds,
            configuration.operations
                .map((operation) => operation.name)
                .join('|'),
            configuration.decimalProbability.toString(),
            configuration.allowedDecimalPlaces.join(','),
            configuration.allowMixedOperations ? 1 : 0,
            configuration.mixedOperationProbability.toString(),
            configuration.answerFeedbackMode.name,
            timestamp,
            SessionLifecycleState.running.name,
          ],
        );
      });
    } on SqliteException catch (error) {
      if (_isForeignKeyError(error)) {
        throw const SessionOwnershipException(
          'The session owner profile does not exist.',
        );
      }
      throw const SessionStorageException(
        'The practice session could not be saved.',
      );
    }
    return (await _loadSession(id))!;
  }

  @override
  Future<void> saveAttempt({
    required String sessionId,
    required String userId,
    required QuestionAttempt attempt,
    required DateTime answeredAt,
  }) async {
    _validateAttempt(attempt);
    try {
      await _database.transaction(() async {
        final session = await _requireOwnedSession(sessionId, userId);
        if (session.read<String>('status') !=
            SessionLifecycleState.running.name) {
          throw const InvalidSessionDataException(
            'Answers can only be saved while a session is running.',
          );
        }
        final count = session.read<int>('attempt_count');
        final configuredCount = session.read<int>('question_count');
        if (attempt.questionNumber <= count) {
          throw DuplicateQuestionAttemptException(
            'Question ${attempt.questionNumber} was already recorded.',
          );
        }
        if (attempt.questionNumber != count + 1 || count >= configuredCount) {
          throw const InvalidSessionDataException(
            'Question attempts must be saved in sequence within the session limit.',
          );
        }
        if (attempt.difficulty.name != session.read<String>('difficulty')) {
          throw const InvalidSessionDataException(
            'The attempt difficulty does not match its session.',
          );
        }
        final startedAt = session.read<int>('started_at_us');
        final answeredAtMicros = _toMicros(answeredAt);
        if (answeredAtMicros < startedAt) {
          throw const InvalidSessionDataException(
            'An answer timestamp cannot precede its session.',
          );
        }
        final activeElapsed =
            answeredAtMicros -
            startedAt -
            session.read<int>('total_paused_time_us');
        if (activeElapsed > session.read<int>('duration_us')) {
          throw const InvalidSessionDataException(
            'An answer cannot be saved after the configured duration.',
          );
        }
        final selectedOperations = session
            .read<String>('operations')
            .split('|');
        if (!selectedOperations.contains(attempt.operation.name)) {
          throw const InvalidSessionDataException(
            'The attempt operation is not selected for this session.',
          );
        }

        await _database.customStatement(
          'INSERT INTO practice_question_attempts '
          '(session_id, sequence_number, expression, operation, difficulty, '
          'correct_numerator, correct_denominator, selected_numerator, '
          'selected_denominator, is_correct, response_time_us, answered_at_us) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            sessionId,
            attempt.questionNumber,
            attempt.expression,
            attempt.operation.name,
            attempt.difficulty.name,
            attempt.correctAnswer.numerator.toString(),
            attempt.correctAnswer.denominator.toString(),
            attempt.selectedAnswer.numerator.toString(),
            attempt.selectedAnswer.denominator.toString(),
            attempt.isCorrect ? 1 : 0,
            attempt.responseTime.inMicroseconds,
            answeredAtMicros,
          ],
        );

        // This counter is the durable sequence cursor used after restart.
        // The insert and cursor update commit or roll back together.
        final changed = await _database.customUpdate(
          'UPDATE practice_sessions SET attempt_count = attempt_count + 1 '
          'WHERE id = ? AND user_id = ? AND attempt_count = ? AND status = ?',
          variables: [
            Variable.withString(sessionId),
            Variable.withString(userId),
            Variable.withInt(count),
            Variable.withString(SessionLifecycleState.running.name),
          ],
        );
        if (changed != 1) {
          throw const SessionStorageException(
            'The attempt cursor could not be updated.',
          );
        }
      });
    } on SqliteException catch (error) {
      if (_isUniqueError(error)) {
        throw DuplicateQuestionAttemptException(
          'Question ${attempt.questionNumber} was already recorded.',
        );
      }
      if (_isForeignKeyError(error)) {
        throw const SessionNotFoundException(
          'The practice session no longer exists.',
        );
      }
      throw const SessionStorageException(
        'The question attempt could not be saved.',
      );
    }
  }

  @override
  Future<void> updateAttempt({
    required String sessionId,
    required String userId,
    required QuestionAttempt attempt,
  }) async {
    _validateAttempt(attempt);
    try {
      await _database.transaction(() async {
        final session = await _requireOwnedSession(sessionId, userId);
        if (session.read<String>('status') !=
            SessionLifecycleState.running.name) {
          throw const InvalidSessionDataException(
            'Answers can only be changed while a session is running.',
          );
        }
        if (attempt.questionNumber > session.read<int>('attempt_count')) {
          throw const InvalidSessionDataException(
            'Only an already answered question can be changed.',
          );
        }
        final original = await _database
            .customSelect(
              'SELECT expression, operation, difficulty, correct_numerator, '
              'correct_denominator FROM practice_question_attempts '
              'WHERE session_id = ? AND sequence_number = ?',
              variables: [
                Variable.withString(sessionId),
                Variable.withInt(attempt.questionNumber),
              ],
            )
            .getSingleOrNull();
        if (original == null) {
          throw const SessionNotFoundException(
            'The answer being changed no longer exists.',
          );
        }
        if (original.read<String>('expression') != attempt.expression ||
            original.read<String>('operation') != attempt.operation.name ||
            original.read<String>('difficulty') != attempt.difficulty.name ||
            original.read<String>('correct_numerator') !=
                attempt.correctAnswer.numerator.toString() ||
            original.read<String>('correct_denominator') !=
                attempt.correctAnswer.denominator.toString()) {
          throw const InvalidSessionDataException(
            'An answer edit cannot change the original question.',
          );
        }
        final changed = await _database.customUpdate(
          'UPDATE practice_question_attempts SET selected_numerator = ?, '
          'selected_denominator = ?, is_correct = ? '
          'WHERE session_id = ? AND sequence_number = ?',
          variables: [
            Variable.withString(attempt.selectedAnswer.numerator.toString()),
            Variable.withString(attempt.selectedAnswer.denominator.toString()),
            Variable.withInt(attempt.isCorrect ? 1 : 0),
            Variable.withString(sessionId),
            Variable.withInt(attempt.questionNumber),
          ],
        );
        if (changed != 1) {
          throw const SessionNotFoundException(
            'The answer being changed no longer exists.',
          );
        }
      });
    } on SqliteException {
      throw const SessionStorageException(
        'The changed answer could not be saved.',
      );
    }
  }

  @override
  Future<PersistedPracticeSession> updateLifecycle({
    required String sessionId,
    required String userId,
    required SessionLifecycleUpdate update,
  }) async {
    _validateLifecycleUpdate(update);
    try {
      await _database.transaction(() async {
        final row = await _requireOwnedSession(sessionId, userId);
        final oldState = SessionLifecycleState.values.byName(
          row.read<String>('status'),
        );
        if (oldState == SessionLifecycleState.completed ||
            oldState == SessionLifecycleState.cancelled) {
          throw const InvalidSessionDataException(
            'A finished session cannot change lifecycle state.',
          );
        }
        if (update.elapsedTime.inMicroseconds <
                row.read<int>('elapsed_time_us') ||
            update.totalPausedTime.inMicroseconds <
                row.read<int>('total_paused_time_us')) {
          throw const InvalidSessionDataException(
            'Persisted session timing cannot move backwards.',
          );
        }
        if (update.elapsedTime >
            Duration(microseconds: row.read<int>('duration_us'))) {
          throw const InvalidSessionDataException(
            'Elapsed time cannot exceed the configured session duration.',
          );
        }
        final changedAt = _toMicros(update.changedAt);
        final startedAt = row.read<int>('started_at_us');
        final pausedAt = update.pausedAt == null
            ? null
            : _toMicros(update.pausedAt!);
        if (changedAt < startedAt ||
            (pausedAt != null &&
                (pausedAt < startedAt || pausedAt > changedAt))) {
          throw const InvalidSessionDataException(
            'Lifecycle timestamps must follow the session start and pause order.',
          );
        }

        final terminal =
            update.state == SessionLifecycleState.completed ||
            update.state == SessionLifecycleState.cancelled;
        await _database.customStatement(
          'UPDATE practice_sessions SET status = ?, ended_at_us = ?, '
          'elapsed_time_us = ?, total_paused_time_us = ?, paused_at_us = ?, '
          'completion_reason = ? WHERE id = ? AND user_id = ?',
          [
            update.state.name,
            terminal ? changedAt : null,
            update.elapsedTime.inMicroseconds,
            update.totalPausedTime.inMicroseconds,
            update.state == SessionLifecycleState.paused ? pausedAt : null,
            terminal ? update.endReason!.name : null,
            sessionId,
            userId,
          ],
        );
      });
    } on SqliteException {
      throw const SessionStorageException(
        'The practice session state could not be updated.',
      );
    }
    return (await _loadSession(sessionId))!;
  }

  @override
  Future<PersistedPracticeSession?> getSession({
    required String sessionId,
    required String userId,
  }) async {
    final row = await _database
        .customSelect(
          'SELECT id FROM practice_sessions WHERE id = ? AND user_id = ?',
          variables: [
            Variable.withString(sessionId),
            Variable.withString(userId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return _loadSession(sessionId);
  }

  @override
  Future<List<PersistedPracticeSession>> listCompletedSessions(
    String userId,
  ) async {
    final rows = await _database
        .customSelect(
          'SELECT id FROM practice_sessions '
          'WHERE user_id = ? AND status = ? ORDER BY ended_at_us DESC, id',
          variables: [
            Variable.withString(userId),
            Variable.withString(SessionLifecycleState.completed.name),
          ],
        )
        .get();
    final sessions = <PersistedPracticeSession>[];
    for (final row in rows) {
      final session = await _loadSession(row.read<String>('id'));
      if (session != null) sessions.add(session);
    }
    return List.unmodifiable(sessions);
  }

  @override
  Future<List<PracticeSessionSummary>> listCompletedSessionSummaries(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    _validatePage(limit, offset);
    try {
      final rows = await _database
          .customSelect(
            'SELECT s.*, COUNT(a.sequence_number) AS summary_attempted_count, '
            'COALESCE(SUM(a.is_correct), 0) AS summary_correct_count '
            'FROM practice_sessions s LEFT JOIN practice_question_attempts a '
            'ON a.session_id = s.id WHERE s.user_id = ? AND s.status = ? '
            'GROUP BY s.id ORDER BY s.ended_at_us DESC, s.id DESC '
            'LIMIT ? OFFSET ?',
            variables: [
              Variable.withString(userId),
              Variable.withString(SessionLifecycleState.completed.name),
              Variable.withInt(limit),
              Variable.withInt(offset),
            ],
          )
          .get();
      return List.unmodifiable(rows.map(_summaryFromRow));
    } on SqliteException {
      throw const SessionStorageException(
        'Practice history could not be loaded.',
      );
    }
  }

  @override
  Future<PracticeStatistics> getStatistics(
    String userId, {
    int recentLimit = 10,
  }) async {
    if (userId.trim().isEmpty) {
      throw const InvalidSessionDataException('A profile is required.');
    }
    if (recentLimit < 1 || recentLimit > 100) {
      throw ArgumentError.value(recentLimit, 'recentLimit');
    }
    try {
      final totals = await _database
          .customSelect(
            'SELECT COUNT(*) AS completed_tests, '
            'COALESCE(SUM(per_session.attempted_count), 0) AS total_attempted, '
            'COALESCE(SUM(per_session.correct_count), 0) AS total_correct, '
            'COALESCE(AVG(CASE WHEN per_session.attempted_count = 0 THEN 0.0 '
            'ELSE per_session.correct_count * 1.0 / '
            'per_session.attempted_count END), 0.0) AS avg_test_accuracy '
            'FROM (SELECT s.id, COUNT(a.sequence_number) AS attempted_count, '
            'COALESCE(SUM(a.is_correct), 0) AS correct_count '
            'FROM practice_sessions s LEFT JOIN practice_question_attempts a '
            'ON a.session_id = s.id WHERE s.user_id = ? AND s.status = ? '
            'GROUP BY s.id) AS per_session',
            variables: [
              Variable.withString(userId),
              Variable.withString(SessionLifecycleState.completed.name),
            ],
          )
          .getSingle();
      final response = await _database
          .customSelect(
            'SELECT COALESCE(AVG(a.response_time_us), 0) AS average_response_us '
            'FROM practice_sessions s JOIN practice_question_attempts a '
            'ON a.session_id = s.id WHERE s.user_id = ? AND s.status = ?',
            variables: [
              Variable.withString(userId),
              Variable.withString(SessionLifecycleState.completed.name),
            ],
          )
          .getSingle();
      final streak = await _database
          .customSelect(
            'WITH correct_rows AS ('
            'SELECT a.session_id, a.sequence_number, '
            'a.sequence_number - ROW_NUMBER() OVER '
            '(PARTITION BY a.session_id ORDER BY a.sequence_number) AS run_key '
            'FROM practice_question_attempts a JOIN practice_sessions s '
            'ON s.id = a.session_id WHERE s.user_id = ? AND s.status = ? '
            'AND a.is_correct = 1), '
            'runs AS (SELECT session_id, run_key, COUNT(*) AS run_length '
            'FROM correct_rows GROUP BY session_id, run_key) '
            'SELECT COALESCE(MAX(run_length), 0) AS best_streak FROM runs',
            variables: [
              Variable.withString(userId),
              Variable.withString(SessionLifecycleState.completed.name),
            ],
          )
          .getSingle();
      final operationRows = await _database
          .customSelect(
            'SELECT a.operation, COUNT(*) AS attempted_count, '
            'COALESCE(SUM(a.is_correct), 0) AS correct_count '
            'FROM practice_sessions s JOIN practice_question_attempts a '
            'ON a.session_id = s.id WHERE s.user_id = ? AND s.status = ? '
            'GROUP BY a.operation',
            variables: [
              Variable.withString(userId),
              Variable.withString(SessionLifecycleState.completed.name),
            ],
          )
          .get();
      final difficultyRows = await _database
          .customSelect(
            'SELECT s.difficulty, COUNT(DISTINCT s.id) AS test_count, '
            'COUNT(a.sequence_number) AS attempted_count, '
            'COALESCE(SUM(a.is_correct), 0) AS correct_count '
            'FROM practice_sessions s LEFT JOIN practice_question_attempts a '
            'ON a.session_id = s.id WHERE s.user_id = ? AND s.status = ? '
            'GROUP BY s.difficulty',
            variables: [
              Variable.withString(userId),
              Variable.withString(SessionLifecycleState.completed.name),
            ],
          )
          .get();

      final byOperation = <ArithmeticOperation, OperationPracticeStatistics>{};
      for (final row in operationRows) {
        final operation = ArithmeticOperation.values.byName(
          row.read<String>('operation'),
        );
        byOperation[operation] = OperationPracticeStatistics(
          operation: operation,
          attemptedCount: row.read<int>('attempted_count'),
          correctCount: row.read<int>('correct_count'),
        );
      }
      for (final operation in ArithmeticOperation.values) {
        byOperation.putIfAbsent(
          operation,
          () => OperationPracticeStatistics(
            operation: operation,
            attemptedCount: 0,
            correctCount: 0,
          ),
        );
      }

      final byDifficulty =
          <ArithmeticDifficulty, DifficultyPracticeStatistics>{};
      for (final row in difficultyRows) {
        final difficulty = ArithmeticDifficulty.values.byName(
          row.read<String>('difficulty'),
        );
        byDifficulty[difficulty] = DifficultyPracticeStatistics(
          difficulty: difficulty,
          completedTestCount: row.read<int>('test_count'),
          attemptedCount: row.read<int>('attempted_count'),
          correctCount: row.read<int>('correct_count'),
        );
      }
      for (final difficulty in ArithmeticDifficulty.values) {
        byDifficulty.putIfAbsent(
          difficulty,
          () => DifficultyPracticeStatistics(
            difficulty: difficulty,
            completedTestCount: 0,
            attemptedCount: 0,
            correctCount: 0,
          ),
        );
      }

      final recent = await listCompletedSessionSummaries(
        userId,
        limit: recentLimit,
      );
      return PracticeStatistics(
        completedTestCount: totals.read<int>('completed_tests'),
        totalAttemptedCount: totals.read<int>('total_attempted'),
        totalCorrectCount: totals.read<int>('total_correct'),
        averageTestAccuracy: totals.read<double>('avg_test_accuracy'),
        averageResponseTime: Duration(
          microseconds: response.read<double>('average_response_us').round(),
        ),
        bestCorrectAnswerStreak: streak.read<int>('best_streak'),
        byOperation: byOperation,
        byDifficulty: byDifficulty,
        recentProgress: recent
            .map(
              (summary) => PracticeProgressPoint(
                completedAt: summary.completedAt,
                attemptedCount: summary.attemptedCount,
                correctCount: summary.correctCount,
              ),
            )
            .toList(growable: false),
      );
    } on SqliteException {
      throw const SessionStorageException(
        'Practice statistics could not be calculated.',
      );
    }
  }

  @override
  Future<SessionResult?> getResult({
    required String sessionId,
    required String userId,
  }) async => (await getSession(sessionId: sessionId, userId: userId))?.result;

  @override
  Future<List<PersistedPracticeSession>> recoverUnfinishedSessions({
    DateTime? recoveredAt,
  }) async {
    final now = _toMicros(recoveredAt ?? _clock());
    final recoveredIds = <String>[];
    try {
      await _database.transaction(() async {
        final rows = await _database
            .customSelect(
              'SELECT * FROM practice_sessions WHERE status IN (?, ?) '
              'ORDER BY started_at_us, id',
              variables: [
                Variable.withString(SessionLifecycleState.running.name),
                Variable.withString(SessionLifecycleState.paused.name),
              ],
            )
            .get();
        for (final row in rows) {
          final wasPaused =
              row.read<String>('status') == SessionLifecycleState.paused.name;
          final startedAt = row.read<int>('started_at_us');
          final duration = row.read<int>('duration_us');
          final elapsed = wasPaused
              ? row.read<int>('elapsed_time_us')
              : _clampElapsed(
                  _max(
                    row.read<int>('elapsed_time_us'),
                    now - startedAt - row.read<int>('total_paused_time_us'),
                  ),
                  duration,
                );
          final endedAt = now < startedAt ? startedAt : now;
          final id = row.read<String>('id');
          await _database.customStatement(
            'UPDATE practice_sessions SET status = ?, ended_at_us = ?, '
            'elapsed_time_us = ?, paused_at_us = NULL, completion_reason = ? '
            'WHERE id = ? AND status IN (?, ?)',
            [
              SessionLifecycleState.cancelled.name,
              endedAt,
              elapsed,
              wasPaused
                  ? SessionEndReason.interruptedWhilePaused.name
                  : SessionEndReason.interruptedWhileRunning.name,
              id,
              SessionLifecycleState.running.name,
              SessionLifecycleState.paused.name,
            ],
          );
          recoveredIds.add(id);
        }
      });
    } on SqliteException {
      throw const SessionStorageException(
        'Unfinished sessions could not be recovered safely.',
      );
    }
    final recovered = <PersistedPracticeSession>[];
    for (final id in recoveredIds) {
      final session = await _loadSession(id);
      if (session != null) recovered.add(session);
    }
    return List.unmodifiable(recovered);
  }

  Future<PersistedPracticeSession?> _loadSession(String id) async {
    final row = await _database
        .customSelect(
          'SELECT * FROM practice_sessions WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    try {
      final attemptRows = await _database
          .customSelect(
            'SELECT * FROM practice_question_attempts '
            'WHERE session_id = ? ORDER BY sequence_number',
            variables: [Variable.withString(id)],
          )
          .get();
      final attempts = attemptRows.map(_attemptFromRow).toList(growable: false);
      if (attempts.length != row.read<int>('attempt_count') ||
          attempts.indexed.any(
            (entry) => entry.$2.questionNumber != entry.$1 + 1,
          )) {
        throw const FormatException(
          'Attempt count does not match stored rows.',
        );
      }
      return PersistedPracticeSession(
        id: id,
        userId: row.read<String>('user_id'),
        configuration: _configurationFromRow(row),
        state: SessionLifecycleState.values.byName(row.read<String>('status')),
        startedAt: _fromMicros(row.read<int>('started_at_us')),
        endedAt: row.readNullable<int>('ended_at_us') == null
            ? null
            : _fromMicros(row.read<int>('ended_at_us')),
        elapsedTime: Duration(microseconds: row.read<int>('elapsed_time_us')),
        totalPausedTime: Duration(
          microseconds: row.read<int>('total_paused_time_us'),
        ),
        pausedAt: row.readNullable<int>('paused_at_us') == null
            ? null
            : _fromMicros(row.read<int>('paused_at_us')),
        endReason: row.readNullable<String>('completion_reason') == null
            ? null
            : SessionEndReason.values.byName(
                row.read<String>('completion_reason'),
              ),
        attempts: attempts,
      );
    } on Object catch (error) {
      if (error is PracticeSessionRepositoryException) rethrow;
      throw SessionStorageException(
        'Stored session data is invalid and could not be read: $error',
      );
    }
  }

  Future<QueryRow> _requireOwnedSession(String sessionId, String userId) async {
    final row = await _database
        .customSelect(
          'SELECT * FROM practice_sessions WHERE id = ?',
          variables: [Variable.withString(sessionId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw const SessionNotFoundException(
        'The practice session does not exist.',
      );
    }
    if (row.read<String>('user_id') != userId) {
      throw const SessionOwnershipException(
        'The practice session belongs to another profile.',
      );
    }
    return row;
  }

  QuestionAttempt _attemptFromRow(QueryRow row) => QuestionAttempt(
    questionNumber: row.read<int>('sequence_number'),
    expression: row.read<String>('expression'),
    operation: ArithmeticOperation.values.byName(row.read<String>('operation')),
    difficulty: ArithmeticDifficulty.values.byName(
      row.read<String>('difficulty'),
    ),
    correctAnswer: _readRational(
      row.read<String>('correct_numerator'),
      row.read<String>('correct_denominator'),
    ),
    selectedAnswer: _readRational(
      row.read<String>('selected_numerator'),
      row.read<String>('selected_denominator'),
    ),
    isCorrect: row.read<int>('is_correct') == 1,
    responseTime: Duration(microseconds: row.read<int>('response_time_us')),
  );

  SessionConfiguration _configurationFromRow(QueryRow row) {
    final operations = row
        .read<String>('operations')
        .split('|')
        .map((value) => ArithmeticOperation.values.byName(value));
    final places = row
        .read<String>('allowed_decimal_places')
        .split(',')
        .map(int.parse);
    return SessionConfiguration(
      difficulty: ArithmeticDifficulty.values.byName(
        row.read<String>('difficulty'),
      ),
      questionCount: row.read<int>('question_count'),
      duration: Duration(microseconds: row.read<int>('duration_us')),
      operations: operations,
      decimalProbability: double.parse(row.read<String>('decimal_probability')),
      allowedDecimalPlaces: places,
      allowMixedOperations: row.read<int>('allow_mixed_operations') == 1,
      mixedOperationProbability: double.parse(
        row.read<String>('mixed_operation_probability'),
      ),
      answerFeedbackMode: AnswerFeedbackMode.values.byName(
        row.read<String>('answer_feedback_mode'),
      ),
    );
  }

  PracticeSessionSummary _summaryFromRow(QueryRow row) =>
      PracticeSessionSummary(
        id: row.read<String>('id'),
        userId: row.read<String>('user_id'),
        configuration: _configurationFromRow(row),
        completedAt: _fromMicros(row.read<int>('ended_at_us')),
        elapsedTime: Duration(microseconds: row.read<int>('elapsed_time_us')),
        attemptedCount: row.read<int>('summary_attempted_count'),
        correctCount: row.read<int>('summary_correct_count'),
      );

  static void _validatePage(int limit, int offset) {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 100.');
    }
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
  }

  void _validateAttempt(QuestionAttempt attempt) {
    if (attempt.questionNumber < 1 ||
        attempt.expression.trim().isEmpty ||
        attempt.responseTime < Duration.zero ||
        attempt.isCorrect !=
            (attempt.selectedAnswer == attempt.correctAnswer)) {
      throw const InvalidSessionDataException(
        'The question attempt contains inconsistent or invalid data.',
      );
    }
  }

  void _validateLifecycleUpdate(SessionLifecycleUpdate update) {
    if (update.state == SessionLifecycleState.idle ||
        update.elapsedTime < Duration.zero ||
        update.totalPausedTime < Duration.zero) {
      throw const InvalidSessionDataException(
        'The lifecycle update contains an invalid state or duration.',
      );
    }
    if ((update.state == SessionLifecycleState.paused) !=
        (update.pausedAt != null)) {
      throw const InvalidSessionDataException(
        'Paused sessions require a pause timestamp and other states cannot have one.',
      );
    }
    final terminal =
        update.state == SessionLifecycleState.completed ||
        update.state == SessionLifecycleState.cancelled;
    if (terminal != (update.endReason != null)) {
      throw const InvalidSessionDataException(
        'Finished sessions require a completion reason.',
      );
    }
    if (update.state == SessionLifecycleState.completed &&
        (update.endReason == SessionEndReason.userCancelled ||
            update.endReason == SessionEndReason.interruptedWhilePaused ||
            update.endReason == SessionEndReason.interruptedWhileRunning)) {
      throw const InvalidSessionDataException(
        'A completed session cannot have a cancellation reason.',
      );
    }
    if (update.state == SessionLifecycleState.cancelled &&
        (update.endReason == SessionEndReason.questionCountReached ||
            update.endReason == SessionEndReason.timeExpired ||
            update.endReason == SessionEndReason.manuallyCompleted)) {
      throw const InvalidSessionDataException(
        'A cancelled session cannot have a completion reason.',
      );
    }
  }

  static Rational _readRational(String numerator, String denominator) {
    final parsedNumerator = BigInt.parse(numerator);
    final parsedDenominator = BigInt.parse(denominator);
    if (parsedDenominator <= BigInt.zero) {
      throw const FormatException('Rational denominator must be positive.');
    }
    return Rational(parsedNumerator, parsedDenominator);
  }

  static int _toMicros(DateTime value) => value.toUtc().microsecondsSinceEpoch;

  static DateTime _fromMicros(int value) =>
      DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);

  static int _clampElapsed(int elapsed, int duration) {
    if (elapsed <= 0) return 0;
    return elapsed > duration ? duration : elapsed;
  }

  static int _max(int first, int second) => first > second ? first : second;

  static bool _isUniqueError(SqliteException error) =>
      error.extendedResultCode == 1555 || error.extendedResultCode == 2067;

  static bool _isForeignKeyError(SqliteException error) =>
      error.extendedResultCode == 787;
}
