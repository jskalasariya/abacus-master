import '../arithmetic/arithmetic_difficulty_config.dart';
import '../arithmetic/arithmetic_operation.dart';
import '../answer_feedback_mode.dart';

/// Immutable, validated rules for one timed practice session.
final class SessionConfiguration {
  factory SessionConfiguration({
    ArithmeticDifficulty difficulty = ArithmeticDifficulty.beginner,
    int questionCount = 100,
    Duration duration = const Duration(minutes: 10),
    Iterable<ArithmeticOperation> operations = ArithmeticOperation.values,
    double? decimalProbability,
    Iterable<int>? allowedDecimalPlaces,
    bool allowMixedOperations = false,
    double mixedOperationProbability = 0,
    AnswerFeedbackMode answerFeedbackMode = AnswerFeedbackMode.immediate,
  }) {
    if (questionCount < 1 || questionCount > maxQuestionCount) {
      throw ArgumentError.value(
        questionCount,
        'questionCount',
        'Must be between 1 and $maxQuestionCount.',
      );
    }
    if (duration <= Duration.zero || duration > maxDuration) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Must be greater than zero and at most 24 hours.',
      );
    }

    final selectedOperations = Set<ArithmeticOperation>.unmodifiable(
      operations,
    );
    if (selectedOperations.isEmpty) {
      throw ArgumentError.value(
        operations,
        'operations',
        'At least one operation must be selected.',
      );
    }

    final difficultyDefaults = ArithmeticDifficultyConfig.defaults[difficulty]!;
    final resolvedDecimalProbability =
        decimalProbability ?? difficultyDefaults.decimalProbability;
    _validateProbability(resolvedDecimalProbability, 'decimalProbability');
    _validateProbability(
      mixedOperationProbability,
      'mixedOperationProbability',
    );
    if (mixedOperationProbability > 0 && !allowMixedOperations) {
      throw ArgumentError(
        'Mixed-operation probability requires allowMixedOperations.',
      );
    }
    if (mixedOperationProbability > 0 &&
        !selectedOperations.containsAll(const {
          ArithmeticOperation.addition,
          ArithmeticOperation.subtraction,
          ArithmeticOperation.multiplication,
        })) {
      throw ArgumentError(
        'Mixed questions require addition, subtraction and multiplication.',
      );
    }

    final places = List<int>.unmodifiable(
      allowedDecimalPlaces ?? difficultyDefaults.allowedDecimalPlaces,
    );
    if (places.isEmpty ||
        places.any((place) => place < 1 || place > 3) ||
        places.toSet().length != places.length) {
      throw ArgumentError.value(
        places,
        'allowedDecimalPlaces',
        'Must contain unique decimal places from 1 through 3.',
      );
    }

    return SessionConfiguration._(
      difficulty: difficulty,
      questionCount: questionCount,
      duration: duration,
      operations: selectedOperations,
      decimalProbability: resolvedDecimalProbability,
      allowedDecimalPlaces: places,
      allowMixedOperations: allowMixedOperations,
      mixedOperationProbability: mixedOperationProbability,
      answerFeedbackMode: answerFeedbackMode,
      allowNegativeResults: difficultyDefaults.allowNegativeResults,
    );
  }

  const SessionConfiguration._({
    required this.difficulty,
    required this.questionCount,
    required this.duration,
    required this.operations,
    required this.decimalProbability,
    required this.allowedDecimalPlaces,
    required this.allowMixedOperations,
    required this.mixedOperationProbability,
    required this.answerFeedbackMode,
    required this.allowNegativeResults,
  });

  static const maxQuestionCount = 1000;
  static const maxDuration = Duration(hours: 24);

  final ArithmeticDifficulty difficulty;
  final int questionCount;
  final Duration duration;
  final Set<ArithmeticOperation> operations;
  final double decimalProbability;
  final List<int> allowedDecimalPlaces;
  final bool allowMixedOperations;
  final double mixedOperationProbability;
  final AnswerFeedbackMode answerFeedbackMode;

  /// Negative answers follow the shared difficulty policy and cannot drift
  /// from the arithmetic question generator's level configuration.
  final bool allowNegativeResults;

  /// Creates the selected level configuration while preserving its operand
  /// and generation limits. The session's decimal and mixed-question choices
  /// override only their corresponding difficulty defaults.
  ArithmeticDifficultyConfig get arithmeticConfiguration {
    final base = ArithmeticDifficultyConfig.defaults[difficulty]!;
    return ArithmeticDifficultyConfig(
      difficulty: difficulty,
      minOperandDigits: base.minOperandDigits,
      maxOperandDigits: base.maxOperandDigits,
      minAdditionOperands: base.minAdditionOperands,
      maxAdditionOperands: base.maxAdditionOperands,
      minSubtractionOperands: base.minSubtractionOperands,
      maxSubtractionOperands: base.maxSubtractionOperands,
      minMultiplicationFactorDigits: base.minMultiplicationFactorDigits,
      maxMultiplicationFactorDigits: base.maxMultiplicationFactorDigits,
      maxDivisionDivisorDigits: base.maxDivisionDivisorDigits,
      maxDivisionQuotientDigits: base.maxDivisionQuotientDigits,
      allowNegativeResults: allowNegativeResults,
      decimalProbability: decimalProbability,
      allowedDecimalPlaces: allowedDecimalPlaces,
      allowRepeatingDivisionResults: base.allowRepeatingDivisionResults,
      mixedOperationProbability: allowMixedOperations
          ? mixedOperationProbability
          : 0,
      minMixedOperations: base.minMixedOperations,
      maxMixedOperations: base.maxMixedOperations,
      maxGenerationAttempts: base.maxGenerationAttempts,
      recentQuestionHistory: base.recentQuestionHistory,
    );
  }

  static void _validateProbability(double value, String name) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'Must be from 0.0 to 1.0.');
    }
  }
}
