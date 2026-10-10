import 'package:abacus_master/application/timed_practice_session_controller.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_difficulty_config.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_operation.dart';
import 'package:abacus_master/domain/arithmetic/calculation_service.dart';
import 'package:abacus_master/domain/arithmetic/rational.dart';
import 'package:abacus_master/domain/sessions/session_configuration.dart';
import 'package:abacus_master/domain/sessions/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionConfiguration', () {
    test('provides the expected defaults and difficulty policy', () {
      final beginner = SessionConfiguration();
      expect(beginner.questionCount, 100);
      expect(beginner.duration, const Duration(minutes: 10));
      expect(beginner.operations, ArithmeticOperation.values.toSet());
      expect(beginner.decimalProbability, 0.12);
      expect(beginner.allowedDecimalPlaces, [1]);
      expect(beginner.allowNegativeResults, isFalse);
      expect(
        SessionConfiguration(difficulty: ArithmeticDifficulty.advanced)
            .allowNegativeResults,
        ArithmeticDifficultyConfig.advanced.allowNegativeResults,
      );
    });

    test('accepts custom question, duration and decimal settings', () {
      final configuration = SessionConfiguration(
        difficulty: ArithmeticDifficulty.medium,
        questionCount: 25,
        duration: const Duration(minutes: 3),
        operations: const {ArithmeticOperation.division},
        decimalProbability: 1,
        allowedDecimalPlaces: const [2, 3],
      );
      expect(configuration.questionCount, 25);
      expect(configuration.operations, {ArithmeticOperation.division});
      expect(configuration.decimalProbability, 1);
      expect(configuration.allowedDecimalPlaces, [2, 3]);
      expect(configuration.arithmeticConfiguration.decimalProbability, 1);
    });

    test('rejects empty operations and nonsensical limits', () {
      expect(
        () => SessionConfiguration(operations: const <ArithmeticOperation>{}),
        throwsArgumentError,
      );
      expect(() => SessionConfiguration(questionCount: 0), throwsArgumentError);
      expect(
        () => SessionConfiguration(questionCount: 1001),
        throwsArgumentError,
      );
      expect(
        () => SessionConfiguration(duration: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => SessionConfiguration(duration: const Duration(days: 2)),
        throwsArgumentError,
      );
      expect(
        () => SessionConfiguration(decimalProbability: 1.1),
        throwsArgumentError,
      );
      expect(
        () => SessionConfiguration(allowedDecimalPlaces: const [2, 2]),
        throwsArgumentError,
      );
      expect(
        () => SessionConfiguration(
          allowMixedOperations: true,
          mixedOperationProbability: 0.5,
          operations: const {ArithmeticOperation.addition},
        ),
        throwsArgumentError,
      );
    });
  });

  group('TimedPracticeSessionController', () {
    test('requires an authenticated owner and starts with exact choices', () {
      final clock = FakeClock();
      String? activeUserId;
      final session = _session(clock, activeUserId: () => activeUserId);

      expect(session.start, throwsStateError);
      expect(session.state, SessionLifecycleState.idle);
      activeUserId = 'learner-1';
      session.start();
      expect(session.state, SessionLifecycleState.running);
      expect(session.userId, 'learner-1');

      final question = session.nextQuestion()!;
      expect(question.number, 1);
      expect(question.options, hasLength(4));
      expect(
        question.options.where((option) => option.isCorrect),
        hasLength(1),
      );
      expect(
        question.options.singleWhere((option) => option.isCorrect).value,
        question.correctAnswer,
      );
      expect(question.question.difficulty, ArithmeticDifficulty.beginner);
    });

    test('generates decimals according to session settings', () {
      final clock = FakeClock();
      final session = _session(
        clock,
        configuration: SessionConfiguration(
          questionCount: 1,
          decimalProbability: 1,
          allowedDecimalPlaces: const [2],
          operations: const {ArithmeticOperation.addition},
        ),
      );
      session.start();
      expect(session.nextQuestion()!.question.decimalPrecision, 2);
    });

    test('uses the selected decimal precision in generated questions', () {
      final clock = FakeClock();
      final session = _session(
        clock,
        configuration: SessionConfiguration(
          difficulty: ArithmeticDifficulty.medium,
          questionCount: 1,
          decimalProbability: 1,
          allowedDecimalPlaces: const [3],
          operations: const {ArithmeticOperation.addition},
        ),
      );
      session.start();

      final generated = session.nextQuestion()!.question;
      expect(generated.difficulty, ArithmeticDifficulty.medium);
      expect(generated.decimalPrecision, 3);
    });

    test('mixed questions use the exact calculation service result', () {
      final clock = FakeClock();
      final session = _session(
        clock,
        configuration: SessionConfiguration(
          allowMixedOperations: true,
          mixedOperationProbability: 1,
        ),
      )..start();
      final prompt = session.nextQuestion()!;
      expect(
        RegExp(r' [+-] | \* ').allMatches(prompt.expression),
        hasLength(2),
      );
      expect(
        const CalculationService().evaluate(prompt.expression),
        prompt.correctAnswer,
      );
    });

    test('records correct and incorrect exact answers exactly once', () {
      final clock = FakeClock();
      final session = _session(
        clock,
        configuration: SessionConfiguration(questionCount: 2),
      )..start();

      final first = session.nextQuestion()!;
      clock.advance(const Duration(seconds: 2));
      expect(
        () => session.submitAnswer(Rational.fromInt(-999999)),
        throwsArgumentError,
      );
      final firstAttempt = session.submitAnswer(first.correctAnswer);
      expect(firstAttempt.isCorrect, isTrue);
      expect(firstAttempt.responseTime, const Duration(seconds: 2));
      expect(session.attempts, hasLength(1));
      final changed = session.submitAnswer(
        first.options.firstWhere((option) => !option.isCorrect).value,
      );
      expect(changed.isCorrect, isFalse);
      expect(changed.responseTime, const Duration(seconds: 2));
      expect(session.attempts, hasLength(1));

      final second = session.nextQuestion()!;
      final wrong = second.options.firstWhere((option) => !option.isCorrect);
      clock.advance(const Duration(seconds: 3));
      final secondAttempt = session.submitAnswer(wrong.value);
      expect(secondAttempt.isCorrect, isFalse);
      expect(session.attempts, hasLength(2));
      expect(session.state, SessionLifecycleState.completed);
      expect(session.result!.userId, 'learner-1');
      expect(session.result!.attemptedCount, 2);
      expect(session.result!.correctCount, 0);
      expect(session.result!.incorrectCount, 2);
      expect(session.result!.accuracy, 0);
      expect(session.result!.elapsedTime, const Duration(seconds: 5));
      expect(
        session.result!.averageResponseTime,
        const Duration(milliseconds: 2500),
      );
      expect(session.result!.bestCorrectAnswerStreak, 0);
      expect(session.nextQuestion(), isNull);
      expect(() => session.submitAnswer(Rational.fromInt(1)), throwsStateError);
    });

    test('finishes when question count is reached', () {
      final clock = FakeClock();
      final session = _session(
        clock,
        configuration: SessionConfiguration(
          questionCount: 1,
          operations: const {ArithmeticOperation.multiplication},
        ),
      )..start();
      final question = session.nextQuestion()!;
      session.submitAnswer(question.correctAnswer);
      expect(session.state, SessionLifecycleState.completed);
      expect(session.result!.attemptedCount, 1);
      expect(session.nextQuestion(), isNull);
    });

    test('duration expiration completes and rejects further answers', () {
      final clock = FakeClock();
      final session = _session(
        clock,
        configuration: SessionConfiguration(
          duration: const Duration(seconds: 5),
        ),
      )..start();
      final question = session.nextQuestion()!;
      clock.advance(const Duration(seconds: 5));
      expect(session.state, SessionLifecycleState.completed);
      expect(session.result!.attemptedCount, 0);
      expect(session.result!.elapsedTime, const Duration(seconds: 5));
      expect(session.nextQuestion(), isNull);
      expect(
        () => session.submitAnswer(question.correctAnswer),
        throwsStateError,
      );
    });

    test('pause time is excluded from elapsed and response time', () {
      final clock = FakeClock();
      final session = _session(
        clock,
        configuration: SessionConfiguration(
          questionCount: 1,
          duration: const Duration(seconds: 20),
        ),
      )..start();
      final question = session.nextQuestion()!;
      clock.advance(const Duration(seconds: 2));
      session.pause();
      expect(session.elapsedTime, const Duration(seconds: 2));
      clock.advance(const Duration(seconds: 10));
      expect(session.elapsedTime, const Duration(seconds: 2));
      session.resume();
      clock.advance(const Duration(seconds: 3));
      final attempt = session.submitAnswer(question.correctAnswer);
      expect(attempt.responseTime, const Duration(seconds: 5));
      expect(session.elapsedTime, const Duration(seconds: 5));
      expect(session.state, SessionLifecycleState.completed);
    });

    test(
      'early completion aggregates streaks and has no post-completion input',
      () {
        final clock = FakeClock();
        final session = _session(
          clock,
          configuration: SessionConfiguration(questionCount: 5),
        )..start();

        for (var index = 0; index < 4; index++) {
          final question = session.nextQuestion()!;
          final answer = index == 2
              ? question.options.firstWhere((option) => !option.isCorrect).value
              : question.correctAnswer;
          clock.advance(const Duration(seconds: 1));
          session.submitAnswer(answer);
        }
        final result = session.complete();
        expect(session.state, SessionLifecycleState.completed);
        expect(result.attemptedCount, 4);
        expect(result.correctCount, 3);
        expect(result.incorrectCount, 1);
        expect(result.bestCorrectAnswerStreak, 2);
        expect(result.averageResponseTime, const Duration(seconds: 1));
        expect(session.currentQuestion, isNull);
        expect(session.nextQuestion(), isNull);
      },
    );

    test('cancellation ends question and cannot accept answers', () {
      final clock = FakeClock();
      final session = _session(clock)..start();
      final question = session.nextQuestion()!;
      session.cancel();
      expect(session.state, SessionLifecycleState.cancelled);
      expect(session.currentQuestion, isNull);
      expect(
        () => session.submitAnswer(question.correctAnswer),
        throwsStateError,
      );
      expect(session.result, isNull);
    });
  });
}

TimedPracticeSessionController _session(
  FakeClock clock, {
  SessionConfiguration? configuration,
  String? Function()? activeUserId,
}) => TimedPracticeSessionController(
  configuration: configuration ?? SessionConfiguration(),
  authenticatedUserId: activeUserId ?? () => 'learner-1',
  clock: clock.call,
  seed: 421,
);

final class FakeClock {
  DateTime value = DateTime.utc(2025, 1, 1);

  DateTime call() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}
