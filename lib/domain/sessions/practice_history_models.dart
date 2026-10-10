import '../arithmetic/arithmetic_operation.dart';
import 'session_configuration.dart';

/// Compact completed-session data for history lists and aggregate reporting.
/// Question details are loaded only after a learner opens a session.
final class PracticeSessionSummary {
  const PracticeSessionSummary({
    required this.id,
    required this.userId,
    required this.configuration,
    required this.completedAt,
    required this.elapsedTime,
    required this.attemptedCount,
    required this.correctCount,
  });

  final String id;
  final String userId;
  final SessionConfiguration configuration;
  final DateTime completedAt;
  final Duration elapsedTime;
  final int attemptedCount;
  final int correctCount;

  double get accuracy =>
      attemptedCount == 0 ? 0 : correctCount / attemptedCount;
}

final class OperationPracticeStatistics {
  const OperationPracticeStatistics({
    required this.operation,
    required this.attemptedCount,
    required this.correctCount,
  });

  final ArithmeticOperation operation;
  final int attemptedCount;
  final int correctCount;

  double get accuracy =>
      attemptedCount == 0 ? 0 : correctCount / attemptedCount;
}

final class DifficultyPracticeStatistics {
  const DifficultyPracticeStatistics({
    required this.difficulty,
    required this.completedTestCount,
    required this.attemptedCount,
    required this.correctCount,
  });

  final ArithmeticDifficulty difficulty;
  final int completedTestCount;
  final int attemptedCount;
  final int correctCount;

  double get accuracy =>
      attemptedCount == 0 ? 0 : correctCount / attemptedCount;
}

final class PracticeProgressPoint {
  const PracticeProgressPoint({
    required this.completedAt,
    required this.attemptedCount,
    required this.correctCount,
  });

  final DateTime completedAt;
  final int attemptedCount;
  final int correctCount;

  double get accuracy =>
      attemptedCount == 0 ? 0 : correctCount / attemptedCount;
}

/// Statistics include completed sessions only. Overall accuracy is weighted
/// by every answered question; averageTestAccuracy gives each completed test
/// equal weight, including a completed test with no answers as zero accuracy.
final class PracticeStatistics {
  PracticeStatistics({
    required this.completedTestCount,
    required this.totalAttemptedCount,
    required this.totalCorrectCount,
    required this.averageTestAccuracy,
    required this.averageResponseTime,
    required this.bestCorrectAnswerStreak,
    required Map<ArithmeticOperation, OperationPracticeStatistics> byOperation,
    required Map<ArithmeticDifficulty, DifficultyPracticeStatistics>
    byDifficulty,
    required List<PracticeProgressPoint> recentProgress,
  }) : byOperation = Map.unmodifiable(byOperation),
       byDifficulty = Map.unmodifiable(byDifficulty),
       recentProgress = List.unmodifiable(recentProgress);

  final int completedTestCount;
  final int totalAttemptedCount;
  final int totalCorrectCount;
  final double averageTestAccuracy;
  final Duration averageResponseTime;
  final int bestCorrectAnswerStreak;
  final Map<ArithmeticOperation, OperationPracticeStatistics> byOperation;
  final Map<ArithmeticDifficulty, DifficultyPracticeStatistics> byDifficulty;
  final List<PracticeProgressPoint> recentProgress;

  double get overallAccuracy =>
      totalAttemptedCount == 0 ? 0 : totalCorrectCount / totalAttemptedCount;
}
