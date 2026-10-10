import '../arithmetic/arithmetic_operation.dart';
import '../arithmetic/arithmetic_question.dart';
import '../arithmetic/multiple_choice_option_generator.dart';
import '../arithmetic/rational.dart';

enum SessionLifecycleState { idle, running, paused, completed, cancelled }

/// Question and shuffled answer choices currently presented by a session.
final class SessionQuestion {
  SessionQuestion({
    required this.number,
    required this.question,
    required List<ArithmeticAnswerOption> options,
  }) : options = List.unmodifiable(options) {
    if (number < 1) throw ArgumentError.value(number, 'number');
    if (this.options.length != 4 ||
        this.options.where((option) => option.isCorrect).length != 1) {
      throw ArgumentError(
        'A session question must have four choices and one correct answer.',
      );
    }
    if (this.options.map((option) => option.value).toSet().length != 4 ||
        this.options.singleWhere((option) => option.isCorrect).value !=
            question.correctAnswer) {
      throw ArgumentError(
        'Session choices must be unique and mark the exact answer as correct.',
      );
    }
  }

  final int number;
  final ArithmeticQuestion question;
  final List<ArithmeticAnswerOption> options;

  String get expression => question.expression;
  Rational get correctAnswer => question.correctAnswer;
  ArithmeticOperation get operation => question.operation;
}

/// Immutable record of one submitted answer.
final class QuestionAttempt {
  const QuestionAttempt({
    required this.questionNumber,
    required this.expression,
    required this.correctAnswer,
    required this.selectedAnswer,
    required this.isCorrect,
    required this.responseTime,
    required this.operation,
    required this.difficulty,
  }) : assert(questionNumber > 0),
       assert(responseTime >= Duration.zero);

  final int questionNumber;
  final String expression;
  final Rational correctAnswer;
  final Rational selectedAnswer;
  final bool isCorrect;
  final Duration responseTime;
  final ArithmeticOperation operation;
  final ArithmeticDifficulty difficulty;
}

/// A completed or explicitly ended session's aggregate result.
final class SessionResult {
  SessionResult({
    required this.userId,
    required List<QuestionAttempt> attempts,
    required this.elapsedTime,
  }) : attempts = List.unmodifiable(attempts) {
    if (userId.trim().isEmpty) throw ArgumentError.value(userId, 'userId');
    if (elapsedTime < Duration.zero) {
      throw ArgumentError.value(elapsedTime, 'elapsedTime');
    }
    if (this.attempts.any((attempt) => attempt.responseTime < Duration.zero)) {
      throw ArgumentError('Response times cannot be negative.');
    }
    final correctCount = this.attempts
        .where((attempt) => attempt.isCorrect)
        .length;
    final responseTotal = this.attempts.fold<int>(
      0,
      (total, attempt) => total + attempt.responseTime.inMicroseconds,
    );
    var currentStreak = 0;
    var bestStreak = 0;
    for (final attempt in this.attempts) {
      if (attempt.isCorrect) {
        currentStreak++;
        if (currentStreak > bestStreak) bestStreak = currentStreak;
      } else {
        currentStreak = 0;
      }
    }

    attemptedCount = this.attempts.length;
    this.correctCount = correctCount;
    incorrectCount = attemptedCount - correctCount;
    accuracy = attemptedCount == 0 ? 0 : correctCount / attemptedCount;
    averageResponseTime = attemptedCount == 0
        ? Duration.zero
        : Duration(microseconds: responseTotal ~/ attemptedCount);
    bestCorrectAnswerStreak = bestStreak;
  }

  final String userId;
  final List<QuestionAttempt> attempts;
  final Duration elapsedTime;
  late final int attemptedCount;
  late final int correctCount;
  late final int incorrectCount;

  /// Fraction in the range 0..1. Exact arithmetic remains in the attempt data.
  late final double accuracy;
  late final Duration averageResponseTime;
  late final int bestCorrectAnswerStreak;
}
