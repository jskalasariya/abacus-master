import 'package:abacus_master/data/database/app_database.dart';
import 'package:abacus_master/data/profiles/sqlite_profile_repository.dart';
import 'package:abacus_master/data/sessions/sqlite_practice_session_repository.dart';
import 'package:abacus_master/data/security/argon2_password_hasher.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_operation.dart';
import 'package:abacus_master/domain/arithmetic/rational.dart';
import 'package:abacus_master/domain/answer_feedback_mode.dart';
import 'package:abacus_master/domain/sessions/practice_session.dart';
import 'package:abacus_master/domain/sessions/practice_session_repository.dart';
import 'package:abacus_master/domain/sessions/session_configuration.dart';
import 'package:abacus_master/domain/sessions/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late SqliteProfileRepository profiles;
  late SqlitePracticeSessionRepository sessions;
  var now = DateTime.utc(2026, 6, 1, 12);
  var userNumber = 0;

  setUp(() {
    database = AppDatabase.inMemory();
    profiles = SqliteProfileRepository(
      database,
      passwordHasher: _TestPasswordHasher(),
      clock: () => now,
    );
    sessions = SqlitePracticeSessionRepository(database, clock: () => now);
    userNumber = 0;
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> createUser() async {
    userNumber++;
    final profile = await profiles.createProfile(
      username: 'session_user_$userNumber',
      password: 'secure passphrase',
    );
    return profile.id;
  }

  Future<PersistedPracticeSession> createSession(
    String userId, {
    SessionConfiguration? configuration,
    DateTime? startedAt,
  }) => sessions.createSession(
    userId: userId,
    configuration: configuration ?? SessionConfiguration(),
    startedAt: startedAt ?? now,
  );

  Future<PersistedPracticeSession> completeSession(
    String owner, {
    required DateTime startedAt,
    required SessionConfiguration configuration,
    required List<QuestionAttempt> attempts,
  }) async {
    final session = await createSession(
      owner,
      configuration: configuration,
      startedAt: startedAt,
    );
    for (var index = 0; index < attempts.length; index++) {
      await sessions.saveAttempt(
        sessionId: session.id,
        userId: owner,
        attempt: attempts[index],
        answeredAt: startedAt.add(Duration(seconds: index + 1)),
      );
    }
    return sessions.updateLifecycle(
      sessionId: session.id,
      userId: owner,
      update: SessionLifecycleUpdate(
        state: SessionLifecycleState.completed,
        changedAt: startedAt.add(const Duration(seconds: 20)),
        elapsedTime: const Duration(seconds: 20),
        totalPausedTime: Duration.zero,
        endReason: SessionEndReason.manuallyCompleted,
      ),
    );
  }

  test('creates and retrieves a session configuration and lifecycle', () async {
    final owner = await createUser();
    final created = await createSession(
      owner,
      configuration: SessionConfiguration(
        difficulty: ArithmeticDifficulty.medium,
        questionCount: 23,
        duration: const Duration(minutes: 4),
        operations: const {ArithmeticOperation.division},
        decimalProbability: 0.375,
        allowedDecimalPlaces: const [2, 3],
        answerFeedbackMode: AnswerFeedbackMode.endOfTest,
      ),
    );

    final retrieved = await sessions.getSession(
      sessionId: created.id,
      userId: owner,
    );
    expect(retrieved, isNotNull);
    expect(retrieved!.userId, owner);
    expect(retrieved.state, SessionLifecycleState.running);
    expect(retrieved.startedAt, now);
    expect(retrieved.configuration.difficulty, ArithmeticDifficulty.medium);
    expect(retrieved.configuration.questionCount, 23);
    expect(retrieved.configuration.duration, const Duration(minutes: 4));
    expect(retrieved.configuration.operations, {ArithmeticOperation.division});
    expect(retrieved.configuration.decimalProbability, 0.375);
    expect(retrieved.configuration.allowedDecimalPlaces, [2, 3]);
    expect(
      retrieved.configuration.answerFeedbackMode,
      AnswerFeedbackMode.endOfTest,
    );
    expect(retrieved.attempts, isEmpty);
    expect(created.id, isNotEmpty);
    expect(created.elapsedTime, Duration.zero);
  });

  test('history and statistics are empty without completed sessions', () async {
    final owner = await createUser();
    final history = await sessions.listCompletedSessionSummaries(owner);
    final statistics = await sessions.getStatistics(owner);

    expect(history, isEmpty);
    expect(statistics.completedTestCount, 0);
    expect(statistics.totalAttemptedCount, 0);
    expect(statistics.totalCorrectCount, 0);
    expect(statistics.overallAccuracy, 0);
    expect(statistics.averageTestAccuracy, 0);
    expect(statistics.averageResponseTime, Duration.zero);
    expect(statistics.bestCorrectAnswerStreak, 0);
    expect(statistics.recentProgress, isEmpty);
    expect(
      statistics.byOperation.values.every((item) => item.accuracy == 0),
      isTrue,
    );
  });

  test(
    'history is newest first, paged, scoped, and reviews saved attempts',
    () async {
      final owner = await createUser();
      final otherOwner = await createUser();
      final base = now;
      final config = SessionConfiguration(
        questionCount: 2,
        operations: const {ArithmeticOperation.addition},
        decimalProbability: 0.5,
        allowedDecimalPlaces: const [1, 2],
      );
      final older = await completeSession(
        owner,
        startedAt: base,
        configuration: config,
        attempts: [_attempt(number: 1, correct: Rational.fromInt(4))],
      );
      final newer = await completeSession(
        owner,
        startedAt: base.add(const Duration(days: 1)),
        configuration: config,
        attempts: [
          _attempt(
            number: 1,
            correct: Rational.fromInt(8),
            selected: Rational.fromInt(7),
            isCorrect: false,
          ),
        ],
      );
      await completeSession(
        otherOwner,
        startedAt: base.add(const Duration(days: 2)),
        configuration: config,
        attempts: [_attempt(number: 1, correct: Rational.fromInt(9))],
      );

      final firstPage = await sessions.listCompletedSessionSummaries(
        owner,
        limit: 1,
      );
      final secondPage = await sessions.listCompletedSessionSummaries(
        owner,
        limit: 1,
        offset: 1,
      );
      expect(firstPage, hasLength(1));
      expect(firstPage.single.id, newer.id);
      expect(firstPage.single.correctCount, 0);
      expect(firstPage.single.accuracy, 0);
      expect(firstPage.single.configuration.allowedDecimalPlaces, [1, 2]);
      expect(secondPage.single.id, older.id);
      expect(
        await sessions.listCompletedSessionSummaries(otherOwner, limit: 20),
        hasLength(1),
      );

      final review = await sessions.getSession(
        sessionId: newer.id,
        userId: owner,
      );
      expect(review!.attempts.single.expression, '(2) + (2)');
      expect(review.attempts.single.selectedAnswer, Rational.fromInt(7));
      expect(review.attempts.single.correctAnswer, Rational.fromInt(8));
      expect(
        await sessions.getSession(sessionId: newer.id, userId: otherOwner),
        isNull,
      );
    },
  );

  test('statistics aggregate edited completed answers and exclude cancelled sessions', () async {
    final owner = await createUser();
    final otherOwner = await createUser();
    final base = now;
    final beginner = SessionConfiguration(
      questionCount: 2,
      difficulty: ArithmeticDifficulty.beginner,
      operations: const {
        ArithmeticOperation.addition,
        ArithmeticOperation.subtraction,
      },
      decimalProbability: 0,
    );
    final first = await createSession(
      owner,
      configuration: beginner,
      startedAt: base,
    );
    final original = _attempt(
      number: 1,
      correct: Rational.fromInt(10),
      selected: Rational.fromInt(8),
      isCorrect: false,
      responseTime: const Duration(seconds: 2),
    );
    await sessions.saveAttempt(
      sessionId: first.id,
      userId: owner,
      attempt: original,
      answeredAt: base.add(const Duration(seconds: 1)),
    );
    await sessions.saveAttempt(
      sessionId: first.id,
      userId: owner,
      attempt: _attempt(
        number: 2,
        correct: Rational.fromInt(5),
        selected: Rational.fromInt(6),
        isCorrect: false,
        operation: ArithmeticOperation.subtraction,
        responseTime: const Duration(seconds: 4),
      ),
      answeredAt: base.add(const Duration(seconds: 2)),
    );
    await sessions.updateAttempt(
      sessionId: first.id,
      userId: owner,
      attempt: QuestionAttempt(
        questionNumber: original.questionNumber,
        expression: original.expression,
        correctAnswer: original.correctAnswer,
        selectedAnswer: original.correctAnswer,
        isCorrect: true,
        responseTime: original.responseTime,
        operation: original.operation,
        difficulty: original.difficulty,
      ),
    );
    await sessions.updateLifecycle(
      sessionId: first.id,
      userId: owner,
      update: SessionLifecycleUpdate(
        state: SessionLifecycleState.completed,
        changedAt: base.add(const Duration(seconds: 20)),
        elapsedTime: const Duration(seconds: 20),
        totalPausedTime: Duration.zero,
        endReason: SessionEndReason.questionCountReached,
      ),
    );

    final medium = SessionConfiguration(
      questionCount: 2,
      difficulty: ArithmeticDifficulty.medium,
      operations: const {
        ArithmeticOperation.multiplication,
        ArithmeticOperation.division,
      },
      decimalProbability: 0,
    );
    await completeSession(
      owner,
      startedAt: base.add(const Duration(days: 1)),
      configuration: medium,
      attempts: [
        _attempt(
          number: 1,
          correct: Rational.fromInt(12),
          operation: ArithmeticOperation.multiplication,
          difficulty: ArithmeticDifficulty.medium,
          responseTime: const Duration(seconds: 6),
        ),
        _attempt(
          number: 2,
          correct: Rational.fromInt(3),
          operation: ArithmeticOperation.division,
          difficulty: ArithmeticDifficulty.medium,
          responseTime: const Duration(seconds: 8),
        ),
      ],
    );
    await completeSession(
      owner,
      startedAt: base.add(const Duration(days: 2)),
      configuration: SessionConfiguration(
        difficulty: ArithmeticDifficulty.advanced,
        questionCount: 1,
      ),
      attempts: const [],
    );

    final cancelled = await createSession(
      owner,
      configuration: beginner,
      startedAt: base.add(const Duration(days: 3)),
    );
    await sessions.saveAttempt(
      sessionId: cancelled.id,
      userId: owner,
      attempt: _attempt(number: 1, correct: Rational.fromInt(1)),
      answeredAt: base.add(const Duration(days: 3, seconds: 1)),
    );
    await sessions.updateLifecycle(
      sessionId: cancelled.id,
      userId: owner,
      update: SessionLifecycleUpdate(
        state: SessionLifecycleState.cancelled,
        changedAt: base.add(const Duration(days: 3, seconds: 20)),
        elapsedTime: const Duration(seconds: 20),
        totalPausedTime: Duration.zero,
        endReason: SessionEndReason.userCancelled,
      ),
    );
    await completeSession(
      otherOwner,
      startedAt: base.add(const Duration(days: 4)),
      configuration: beginner,
      attempts: [_attempt(number: 1, correct: Rational.fromInt(1))],
    );

    final stats = await sessions.getStatistics(owner);
    expect(stats.completedTestCount, 3);
    expect(stats.totalAttemptedCount, 4);
    expect(stats.totalCorrectCount, 3);
    expect(stats.overallAccuracy, 0.75);
    expect(stats.averageTestAccuracy, 0.5);
    expect(stats.averageResponseTime, const Duration(seconds: 5));
    expect(stats.bestCorrectAnswerStreak, 2);
    expect(stats.byOperation[ArithmeticOperation.addition]!.attemptedCount, 1);
    expect(stats.byOperation[ArithmeticOperation.addition]!.correctCount, 1);
    expect(stats.byOperation[ArithmeticOperation.subtraction]!.correctCount, 0);
    expect(
      stats.byOperation[ArithmeticOperation.multiplication]!.correctCount,
      1,
    );
    expect(stats.byOperation[ArithmeticOperation.division]!.correctCount, 1);
    expect(
      stats.byDifficulty[ArithmeticDifficulty.beginner]!.attemptedCount,
      2,
    );
    expect(
      stats.byDifficulty[ArithmeticDifficulty.medium]!.completedTestCount,
      1,
    );
    expect(stats.byDifficulty[ArithmeticDifficulty.advanced]!.accuracy, 0);
    expect(stats.recentProgress, hasLength(3));
    expect(stats.recentProgress.first.attemptedCount, 0);
    expect((await sessions.listCompletedSessionSummaries(owner)), hasLength(3));
  });

  test(
    'stores exact rational answers and prevents duplicate attempts',
    () async {
      final owner = await createUser();
      final session = await createSession(owner);
      final exact = Rational(
        BigInt.parse('123456789012345678901234567890123456789'),
        BigInt.from(97),
      );
      final attempt = _attempt(
        number: 1,
        correct: exact,
        selected: Rational.fromInt(2),
        isCorrect: false,
        responseTime: const Duration(seconds: 2),
      );
      await sessions.saveAttempt(
        sessionId: session.id,
        userId: owner,
        attempt: attempt,
        answeredAt: now.add(const Duration(seconds: 5)),
      );

      final retrieved = (await sessions.getSession(
        sessionId: session.id,
        userId: owner,
      ))!;
      expect(retrieved.attempts.single.correctAnswer, exact);
      expect(
        retrieved.attempts.single.correctAnswer.numerator,
        exact.numerator,
      );
      expect(
        retrieved.attempts.single.correctAnswer.denominator,
        exact.denominator,
      );
      expect(retrieved.attempts.single.selectedAnswer, Rational.fromInt(2));
      expect(retrieved.attempts.single.isCorrect, isFalse);
      expect(
        retrieved.attempts.single.responseTime,
        const Duration(seconds: 2),
      );

      await expectLater(
        sessions.saveAttempt(
          sessionId: session.id,
          userId: owner,
          attempt: attempt,
          answeredAt: now.add(const Duration(seconds: 6)),
        ),
        throwsA(isA<DuplicateQuestionAttemptException>()),
      );
      expect(
        (await sessions.getSession(
          sessionId: session.id,
          userId: owner,
        ))!.attempts,
        hasLength(1),
      );
    },
  );

  test(
    'reconstructs completed result and lists only the owning user sessions',
    () async {
      final owner = await createUser();
      final otherOwner = await createUser();
      final session = await createSession(
        owner,
        configuration: SessionConfiguration(questionCount: 3),
      );
      await sessions.saveAttempt(
        sessionId: session.id,
        userId: owner,
        attempt: _attempt(number: 1, correct: Rational.fromInt(4)),
        answeredAt: now.add(const Duration(seconds: 2)),
      );
      await sessions.saveAttempt(
        sessionId: session.id,
        userId: owner,
        attempt: _attempt(
          number: 2,
          correct: Rational.fromInt(5),
          selected: Rational.fromInt(6),
          isCorrect: false,
          responseTime: const Duration(seconds: 2),
        ),
        answeredAt: now.add(const Duration(seconds: 5)),
      );
      await sessions.saveAttempt(
        sessionId: session.id,
        userId: owner,
        attempt: _attempt(
          number: 3,
          correct: Rational.fromInt(7),
          responseTime: const Duration(seconds: 3),
        ),
        answeredAt: now.add(const Duration(seconds: 9)),
      );
      final completed = await sessions.updateLifecycle(
        sessionId: session.id,
        userId: owner,
        update: SessionLifecycleUpdate(
          state: SessionLifecycleState.completed,
          changedAt: now.add(const Duration(seconds: 10)),
          elapsedTime: const Duration(seconds: 10),
          totalPausedTime: Duration.zero,
          endReason: SessionEndReason.questionCountReached,
        ),
      );

      expect(completed.endedAt, now.add(const Duration(seconds: 10)));
      expect(completed.endReason, SessionEndReason.questionCountReached);
      final result = await sessions.getResult(
        sessionId: session.id,
        userId: owner,
      );
      expect(result, isNotNull);
      expect(result!.userId, owner);
      expect(result.attemptedCount, 3);
      expect(result.correctCount, 2);
      expect(result.incorrectCount, 1);
      expect(result.accuracy, 2 / 3);
      expect(result.elapsedTime, const Duration(seconds: 10));
      expect(result.averageResponseTime, const Duration(seconds: 2));
      expect(result.bestCorrectAnswerStreak, 1);
      expect(await sessions.listCompletedSessions(owner), hasLength(1));
      expect(await sessions.listCompletedSessions(otherOwner), isEmpty);
      expect(
        await sessions.getSession(sessionId: session.id, userId: otherOwner),
        isNull,
      );
    },
  );

  test('rejects writes by another user and inconsistent correctness', () async {
    final owner = await createUser();
    final otherOwner = await createUser();
    final session = await createSession(owner);
    await expectLater(
      sessions.saveAttempt(
        sessionId: session.id,
        userId: otherOwner,
        attempt: _attempt(number: 1, correct: Rational.fromInt(1)),
        answeredAt: now,
      ),
      throwsA(isA<SessionOwnershipException>()),
    );
    await expectLater(
      sessions.saveAttempt(
        sessionId: session.id,
        userId: owner,
        attempt: _attempt(
          number: 1,
          correct: Rational.fromInt(1),
          selected: Rational.fromInt(2),
          isCorrect: true,
        ),
        answeredAt: now,
      ),
      throwsA(isA<InvalidSessionDataException>()),
    );
  });

  test('rolls back the attempt insert if the cursor update fails', () async {
    final owner = await createUser();
    final session = await createSession(owner);
    await database.customStatement('''
      CREATE TRIGGER fail_attempt_cursor
      BEFORE UPDATE OF attempt_count ON practice_sessions
      BEGIN SELECT RAISE(ABORT, 'forced test failure'); END
    ''');

    await expectLater(
      sessions.saveAttempt(
        sessionId: session.id,
        userId: owner,
        attempt: _attempt(number: 1, correct: Rational.fromInt(1)),
        answeredAt: now,
      ),
      throwsA(isA<SessionStorageException>()),
    );
    final retrieved = (await sessions.getSession(
      sessionId: session.id,
      userId: owner,
    ))!;
    expect(retrieved.attempts, isEmpty);
  });

  test('cascades profile deletion to practice sessions and attempts', () async {
    final owner = await createUser();
    final session = await createSession(owner);
    await sessions.saveAttempt(
      sessionId: session.id,
      userId: owner,
      attempt: _attempt(number: 1, correct: Rational.fromInt(1)),
      answeredAt: now,
    );

    expect(await profiles.deleteProfile(owner), isTrue);
    expect(
      await sessions.getSession(sessionId: session.id, userId: owner),
      isNull,
    );
    expect(
      (await database
              .customSelect(
                'SELECT COUNT(*) AS count FROM practice_question_attempts',
              )
              .getSingle())
          .read<int>('count'),
      0,
    );
  });

  test(
    'recovers running and paused sessions without inventing attempts',
    () async {
      final owner = await createUser();
      final startedAt = now;
      final running = await createSession(
        owner,
        configuration: SessionConfiguration(
          duration: const Duration(seconds: 10),
        ),
        startedAt: startedAt,
      );
      await sessions.saveAttempt(
        sessionId: running.id,
        userId: owner,
        attempt: _attempt(number: 1, correct: Rational.fromInt(1)),
        answeredAt: startedAt.add(const Duration(seconds: 1)),
      );

      final pausedSession = await createSession(
        owner,
        configuration: SessionConfiguration(
          duration: const Duration(minutes: 1),
        ),
        startedAt: startedAt,
      );
      await sessions.updateLifecycle(
        sessionId: pausedSession.id,
        userId: owner,
        update: SessionLifecycleUpdate(
          state: SessionLifecycleState.paused,
          changedAt: startedAt.add(const Duration(seconds: 2)),
          elapsedTime: const Duration(seconds: 2),
          totalPausedTime: Duration.zero,
          pausedAt: startedAt.add(const Duration(seconds: 2)),
        ),
      );

      final recovered = await sessions.recoverUnfinishedSessions(
        recoveredAt: startedAt.add(const Duration(seconds: 30)),
      );
      expect(recovered, hasLength(2));
      final runningRecovery = recovered.singleWhere(
        (item) => item.id == running.id,
      );
      expect(runningRecovery.state, SessionLifecycleState.cancelled);
      expect(
        runningRecovery.endReason,
        SessionEndReason.interruptedWhileRunning,
      );
      expect(runningRecovery.elapsedTime, const Duration(seconds: 10));
      expect(runningRecovery.attempts, hasLength(1));
      final pausedRecovery = recovered.singleWhere(
        (item) => item.id == pausedSession.id,
      );
      expect(pausedRecovery.state, SessionLifecycleState.cancelled);
      expect(pausedRecovery.endReason, SessionEndReason.interruptedWhilePaused);
      expect(pausedRecovery.elapsedTime, const Duration(seconds: 2));
      expect(pausedRecovery.attempts, isEmpty);
      expect(
        await sessions.recoverUnfinishedSessions(recoveredAt: now),
        isEmpty,
      );
    },
  );
}

QuestionAttempt _attempt({
  required int number,
  required Rational correct,
  Rational? selected,
  bool isCorrect = true,
  Duration responseTime = const Duration(seconds: 1),
  ArithmeticOperation operation = ArithmeticOperation.addition,
  ArithmeticDifficulty difficulty = ArithmeticDifficulty.beginner,
}) => QuestionAttempt(
  questionNumber: number,
  expression: '(2) + (2)',
  operation: operation,
  difficulty: difficulty,
  correctAnswer: correct,
  selectedAnswer: selected ?? correct,
  isCorrect: isCorrect,
  responseTime: responseTime,
);

final class _TestPasswordHasher implements PasswordHasher {
  @override
  Future<String> hash(String password) async => 'test-hash:$password';

  @override
  Future<bool> verify(String password, String encodedHash) async =>
      encodedHash == await hash(password);
}
