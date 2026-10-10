import 'package:abacus_master/application/practice_session_coordinator.dart';
import 'package:abacus_master/data/database/app_database.dart';
import 'package:abacus_master/data/profiles/sqlite_profile_repository.dart';
import 'package:abacus_master/data/sessions/sqlite_practice_session_repository.dart';
import 'package:abacus_master/data/security/argon2_password_hasher.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_operation.dart';
import 'package:abacus_master/domain/answer_feedback_mode.dart';
import 'package:abacus_master/domain/sessions/practice_session.dart';
import 'package:abacus_master/domain/sessions/practice_history_models.dart';
import 'package:abacus_master/domain/sessions/practice_session_repository.dart';
import 'package:abacus_master/domain/sessions/session_configuration.dart';
import 'package:abacus_master/domain/sessions/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late SqliteProfileRepository profiles;
  late SqlitePracticeSessionRepository repository;
  late _Clock clock;
  late String owner;

  setUp(() async {
    database = AppDatabase.inMemory();
    clock = _Clock(DateTime.utc(2026, 10, 10));
    profiles = SqliteProfileRepository(
      database,
      passwordHasher: _Hasher(),
      clock: clock.call,
    );
    repository = SqlitePracticeSessionRepository(database, clock: clock.call);
    owner = (await profiles.createProfile(
      username: 'practice_owner',
      password: 'safe password',
    )).id;
  });

  tearDown(() async => database.close());

  PracticeSessionCoordinator coordinatorFor({
    String? Function()? activeUser,
    required SessionConfiguration configuration,
    PracticeSessionRepository? usingRepository,
  }) {
    return PracticeSessionCoordinator(
      configuration: configuration,
      authenticatedUserId: activeUser ?? () => owner,
      repository: usingRepository ?? repository,
      clock: clock.call,
      seed: 42,
    );
  }

  test('requires authentication and persists the correct owner', () async {
    String? activeUser;
    final session = coordinatorFor(
      activeUser: () => activeUser,
      configuration: _configuration(),
    );
    await expectLater(
      session.start(),
      throwsA(isA<UnauthenticatedSessionException>()),
    );
    activeUser = owner;
    await session.start();
    final stored = await repository.getSession(
      sessionId: session.sessionId!,
      userId: owner,
    );
    expect(stored!.userId, owner);
    expect(stored.state, SessionLifecycleState.running);
    expect(session.userId, owner);
  });

  test(
    'answer writes once before the controller advances and rebuilds result',
    () async {
      final session = coordinatorFor(
        configuration: _configuration(questionCount: 1),
      );
      await session.start();
      final question = await session.nextQuestion();
      final selected = question!.options.singleWhere(
        (option) => option.isCorrect,
      );
      clock.advance(const Duration(seconds: 3));
      final accepted = await session.submitAnswer(selected.value);

      expect(accepted.isCorrect, isTrue);
      expect(session.attemptedCount, 1);
      expect(session.state, SessionLifecycleState.completed);
      final stored = await repository.getSession(
        sessionId: session.sessionId!,
        userId: owner,
      );
      expect(stored!.attempts, hasLength(1));
      expect(stored.attempts.single.responseTime, const Duration(seconds: 3));
      final result = await repository.getResult(
        sessionId: session.sessionId!,
        userId: owner,
      );
      expect(result!.correctCount, 1);
      expect(result.bestCorrectAnswerStreak, 1);
      expect(result.userId, owner);
    },
  );

  test(
    'ten-question completion stores ten attempts and reconstructs result',
    () async {
      final session = coordinatorFor(
        configuration: _configuration(questionCount: 10),
      );
      await session.start();
      for (var questionNumber = 1; questionNumber <= 10; questionNumber++) {
        final question = (await session.nextQuestion())!;
        expect(question.number, questionNumber);
        final selected = question.options
            .singleWhere((option) => option.isCorrect)
            .value;
        if (questionNumber == 10) {
          // A countdown synchronization can overlap the final tap on a slower
          // device. Both operations must be serialized instead of rejecting the
          // answer with a transient in-progress StateError.
          await Future.wait<void>([
            session.synchronize(),
            session.submitAnswer(selected).then<void>((_) {}),
          ]);
        } else {
          await session.submitAnswer(selected);
        }
        clock.advance(const Duration(milliseconds: 100));
      }

      final stored = await repository.getSession(
        sessionId: session.sessionId!,
        userId: owner,
      );
      expect(stored!.state, SessionLifecycleState.completed);
      expect(stored.attempts, hasLength(10));
      expect(
        stored.attempts.map((attempt) => attempt.questionNumber).toList(),
        List<int>.generate(10, (index) => index + 1),
      );
      expect(stored.result!.attemptedCount, 10);
      expect(stored.result!.correctCount, 10);
      expect(stored.result!.incorrectCount, 0);
    },
  );

  test(
    'retry after a post-commit error is idempotent for final answer',
    () async {
      final postCommitError = _ThrowAfterNextSave(repository);
      final session = coordinatorFor(
        configuration: _configuration(questionCount: 10),
        usingRepository: postCommitError,
      );
      await session.start();
      for (var index = 0; index < 9; index++) {
        final question = (await session.nextQuestion())!;
        await session.submitAnswer(
          question.options.singleWhere((option) => option.isCorrect).value,
        );
        clock.advance(const Duration(milliseconds: 100));
      }
      final finalQuestion = (await session.nextQuestion())!;
      final correct = finalQuestion.options.singleWhere(
        (option) => option.isCorrect,
      );
      postCommitError.failNextSave = true;
      await expectLater(
        session.submitAnswer(correct.value),
        throwsA(isA<SessionStorageException>()),
      );
      expect(session.attemptedCount, 9);
      expect(
        (await repository.getSession(
          sessionId: session.sessionId!,
          userId: owner,
        ))!.attempts,
        hasLength(10),
      );

      await session.submitAnswer(correct.value);
      final stored = (await repository.getSession(
        sessionId: session.sessionId!,
        userId: owner,
      ))!;
      expect(stored.state, SessionLifecycleState.completed);
      expect(stored.attempts, hasLength(10));
      expect(stored.result!.attemptedCount, 10);
      expect(stored.result!.correctCount, 10);
      expect(stored.result!.incorrectCount, 0);
    },
  );

  test(
    'revisiting updates the existing answer and keeps first response time',
    () async {
      final session = coordinatorFor(
        configuration: _configuration(questionCount: 3),
      );
      await session.start();
      final first = (await session.nextQuestion())!;
      clock.advance(const Duration(seconds: 2));
      await session.submitAnswer(
        first.options.singleWhere((option) => option.isCorrect).value,
      );
      final second = (await session.nextQuestion())!;
      await session.submitAnswer(
        second.options.firstWhere((option) => !option.isCorrect).value,
      );
      await session.previousQuestion();
      expect(session.currentQuestion!.number, 1);
      final revised = first.options.firstWhere((option) => !option.isCorrect);
      await session.submitAnswer(revised.value);
      expect(session.attemptedCount, 2);
      expect(session.attempts.first.isCorrect, isFalse);
      expect(session.attempts.first.responseTime, const Duration(seconds: 2));
      expect((await session.nextQuestion())!.number, 2);
      await session.complete();

      final stored = (await repository.getSession(
        sessionId: session.sessionId!,
        userId: owner,
      ))!;
      expect(stored.attempts, hasLength(2));
      expect(stored.attempts.first.selectedAnswer, revised.value);
      expect(stored.result!.correctCount, 0);
      expect(stored.result!.incorrectCount, 2);
    },
  );

  test(
    'a failed attempt write keeps the same question available for retry',
    () async {
      final session = coordinatorFor(configuration: _configuration());
      await session.start();
      final question = await session.nextQuestion();
      await database.customStatement('''
      CREATE TRIGGER fail_attempt BEFORE INSERT ON practice_question_attempts
      BEGIN SELECT RAISE(ABORT, 'injected write failure'); END
    ''');
      await expectLater(
        session.submitAnswer(question!.options.first.value),
        throwsA(isA<SessionStorageException>()),
      );
      expect(session.attempts, isEmpty);
      expect(session.currentQuestion, same(question));

      await database.customStatement('DROP TRIGGER fail_attempt');
      final accepted = await session.submitAnswer(question.options.first.value);
      expect(accepted.questionNumber, 1);
      expect(session.attempts, hasLength(1));
      final stored = await repository.getSession(
        sessionId: session.sessionId!,
        userId: owner,
      );
      expect(stored!.attempts, hasLength(1));
    },
  );

  test(
    'question navigation does not pause or extend the session clock',
    () async {
      final session = coordinatorFor(
        configuration: _configuration(
          questionCount: 3,
          duration: const Duration(seconds: 20),
        ),
      );
      await session.start();
      final first = (await session.nextQuestion())!;
      clock.advance(const Duration(seconds: 2));
      await session.submitAnswer(
        first.options.singleWhere((option) => option.isCorrect).value,
      );
      final second = (await session.nextQuestion())!;
      await session.submitAnswer(
        second.options.singleWhere((option) => option.isCorrect).value,
      );
      await session.previousQuestion();
      expect(session.currentQuestion!.number, 1);
      clock.advance(const Duration(seconds: 18));
      await session.synchronize();

      expect(session.state, SessionLifecycleState.completed);
      expect(session.elapsedTime, const Duration(seconds: 20));
      expect(session.currentQuestion, isNull);
    },
  );

  test('incorrect selections are saved as incorrect attempts', () async {
    final session = coordinatorFor(configuration: _configuration());
    await session.start();
    final question = await session.nextQuestion();
    final incorrect = question!.options.firstWhere(
      (option) => !option.isCorrect,
    );
    final attempt = await session.submitAnswer(incorrect.value);

    expect(attempt.isCorrect, isFalse);
    final stored = await repository.getSession(
      sessionId: session.sessionId!,
      userId: owner,
    );
    expect(stored!.attempts, hasLength(1));
    expect(stored.attempts.single.isCorrect, isFalse);
  });

  test('feedback mode persists and does not change scoring', () async {
    Future<SessionResult> completeWithMode(AnswerFeedbackMode mode) async {
      final session = coordinatorFor(
        configuration: _configuration(
          questionCount: 2,
          answerFeedbackMode: mode,
        ),
      );
      await session.start();
      final first = (await session.nextQuestion())!;
      await session.submitAnswer(
        first.options.singleWhere((option) => option.isCorrect).value,
      );
      clock.advance(const Duration(seconds: 1));
      final second = (await session.nextQuestion())!;
      await session.submitAnswer(
        second.options.firstWhere((option) => !option.isCorrect).value,
      );
      final stored = await repository.getSession(
        sessionId: session.sessionId!,
        userId: owner,
      );
      expect(stored!.configuration.answerFeedbackMode, mode);
      return stored.result!;
    }

    final immediate = await completeWithMode(AnswerFeedbackMode.immediate);
    final endOfTest = await completeWithMode(AnswerFeedbackMode.endOfTest);
    expect(endOfTest.attemptedCount, immediate.attemptedCount);
    expect(endOfTest.correctCount, immediate.correctCount);
    expect(endOfTest.incorrectCount, immediate.incorrectCount);
    expect(endOfTest.accuracy, immediate.accuracy);
  });

  test(
    'pause-aware timestamps exclude paused time and timeout is persisted',
    () async {
      final session = coordinatorFor(
        configuration: _configuration(duration: const Duration(seconds: 10)),
      );
      await session.start();
      await session.nextQuestion();
      clock.advance(const Duration(seconds: 4));
      await session.pause();
      clock.advance(const Duration(hours: 1));
      expect(session.elapsedTime, const Duration(seconds: 4));
      await session.resume();
      clock.advance(const Duration(seconds: 6));
      await session.synchronize();

      expect(session.state, SessionLifecycleState.completed);
      expect(session.remainingTime, Duration.zero);
      final stored = await repository.getSession(
        sessionId: session.sessionId!,
        userId: owner,
      );
      expect(stored!.state, SessionLifecycleState.completed);
      expect(stored.endReason, SessionEndReason.timeExpired);
      expect(stored.elapsedTime, const Duration(seconds: 10));
      expect(
        stored.attempts,
        isEmpty,
        reason: 'An unanswered question stays unanswered.',
      );
    },
  );

  test(
    'changing profile owner ends the session under its original owner',
    () async {
      final other = (await profiles.createProfile(
        username: 'practice_other',
        password: 'other password',
      )).id;
      var active = owner;
      final session = coordinatorFor(
        activeUser: () => active,
        configuration: _configuration(),
      );
      await session.start();
      active = other;
      await expectLater(
        session.nextQuestion(),
        throwsA(isA<SessionOwnerChangedException>()),
      );

      final original = await repository.getSession(
        sessionId: session.sessionId!,
        userId: owner,
      );
      final otherUserView = await repository.getSession(
        sessionId: session.sessionId!,
        userId: other,
      );
      expect(original!.state, SessionLifecycleState.cancelled);
      expect(original.userId, owner);
      expect(otherUserView, isNull);
    },
  );
}

SessionConfiguration _configuration({
  int questionCount = 3,
  Duration duration = const Duration(minutes: 1),
  AnswerFeedbackMode answerFeedbackMode = AnswerFeedbackMode.immediate,
}) => SessionConfiguration(
  questionCount: questionCount,
  duration: duration,
  operations: const {ArithmeticOperation.addition},
  decimalProbability: 0,
  answerFeedbackMode: answerFeedbackMode,
);

final class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration duration) => now = now.add(duration);
}

final class _Hasher implements PasswordHasher {
  @override
  Future<String> hash(String password) async => 'test:$password';

  @override
  Future<bool> verify(String password, String encodedHash) async =>
      encodedHash == 'test:$password';
}

final class _ThrowAfterNextSave implements PracticeSessionRepository {
  _ThrowAfterNextSave(this.delegate);

  final PracticeSessionRepository delegate;
  bool failNextSave = false;

  @override
  Future<PersistedPracticeSession> createSession({
    required String userId,
    required SessionConfiguration configuration,
    required DateTime startedAt,
  }) => delegate.createSession(
    userId: userId,
    configuration: configuration,
    startedAt: startedAt,
  );

  @override
  Future<void> saveAttempt({
    required String sessionId,
    required String userId,
    required QuestionAttempt attempt,
    required DateTime answeredAt,
  }) async {
    await delegate.saveAttempt(
      sessionId: sessionId,
      userId: userId,
      attempt: attempt,
      answeredAt: answeredAt,
    );
    if (failNextSave) {
      failNextSave = false;
      throw const SessionStorageException('Injected post-commit failure.');
    }
  }

  @override
  Future<void> updateAttempt({
    required String sessionId,
    required String userId,
    required QuestionAttempt attempt,
  }) => delegate.updateAttempt(
    sessionId: sessionId,
    userId: userId,
    attempt: attempt,
  );

  @override
  Future<PersistedPracticeSession> updateLifecycle({
    required String sessionId,
    required String userId,
    required SessionLifecycleUpdate update,
  }) => delegate.updateLifecycle(
    sessionId: sessionId,
    userId: userId,
    update: update,
  );

  @override
  Future<PersistedPracticeSession?> getSession({
    required String sessionId,
    required String userId,
  }) => delegate.getSession(sessionId: sessionId, userId: userId);

  @override
  Future<List<PersistedPracticeSession>> listCompletedSessions(String userId) =>
      delegate.listCompletedSessions(userId);

  @override
  Future<SessionResult?> getResult({
    required String sessionId,
    required String userId,
  }) => delegate.getResult(sessionId: sessionId, userId: userId);

  @override
  Future<List<PracticeSessionSummary>> listCompletedSessionSummaries(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) => delegate.listCompletedSessionSummaries(
    userId,
    limit: limit,
    offset: offset,
  );

  @override
  Future<PracticeStatistics> getStatistics(
    String userId, {
    int recentLimit = 10,
  }) => delegate.getStatistics(userId, recentLimit: recentLimit);

  @override
  Future<List<PersistedPracticeSession>> recoverUnfinishedSessions({
    DateTime? recoveredAt,
  }) => delegate.recoverUnfinishedSessions(recoveredAt: recoveredAt);
}
