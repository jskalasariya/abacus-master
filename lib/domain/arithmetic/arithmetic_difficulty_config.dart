import 'arithmetic_operation.dart';

/// Validated limits and probabilities used to create questions at one level.
///
/// Digit limits refer to the whole-number portion of operands. Decimal places
/// control generated operand notation and preferred answer display precision.
final class ArithmeticDifficultyConfig {
  factory ArithmeticDifficultyConfig({
    required ArithmeticDifficulty difficulty,
    int minOperandDigits = 1,
    int maxOperandDigits = 2,
    int minAdditionOperands = 2,
    int maxAdditionOperands = 3,
    int minSubtractionOperands = 2,
    int maxSubtractionOperands = 2,
    int minMultiplicationFactorDigits = 1,
    int maxMultiplicationFactorDigits = 1,
    int maxDivisionDivisorDigits = 1,
    int maxDivisionQuotientDigits = 1,
    bool allowNegativeResults = false,
    double decimalProbability = 0.0,
    Iterable<int> allowedDecimalPlaces = const [1],
    bool allowRepeatingDivisionResults = false,
    double mixedOperationProbability = 0.0,
    int minMixedOperations = 2,
    int maxMixedOperations = 2,
    int maxGenerationAttempts = 64,
    int recentQuestionHistory = 24,
  }) {
    _validateDigitRange(minOperandDigits, maxOperandDigits, 'operand');
    _validateCountRange(
      minAdditionOperands,
      maxAdditionOperands,
      'addition operands',
    );
    _validateCountRange(
      minSubtractionOperands,
      maxSubtractionOperands,
      'subtraction operands',
    );
    _validateDigitRange(
      minMultiplicationFactorDigits,
      maxMultiplicationFactorDigits,
      'multiplication factor',
    );
    _validateDigitRange(1, maxDivisionDivisorDigits, 'division divisor');
    _validateDigitRange(1, maxDivisionQuotientDigits, 'division quotient');
    _validateProbability(decimalProbability, 'decimalProbability');
    _validateProbability(
      mixedOperationProbability,
      'mixedOperationProbability',
    );
    if (minMixedOperations < 2 ||
        maxMixedOperations < minMixedOperations ||
        maxMixedOperations > 6) {
      throw ArgumentError('Mixed operation counts must be between 2 and 6.');
    }
    if (maxGenerationAttempts < 1) {
      throw ArgumentError.value(
        maxGenerationAttempts,
        'maxGenerationAttempts',
        'Must be positive.',
      );
    }
    if (recentQuestionHistory < 0) {
      throw ArgumentError.value(
        recentQuestionHistory,
        'recentQuestionHistory',
        'Must not be negative.',
      );
    }

    final places = List<int>.unmodifiable(allowedDecimalPlaces);
    if (places.isEmpty ||
        places.any((place) => place < 1 || place > 3) ||
        places.toSet().length != places.length) {
      throw ArgumentError.value(
        places,
        'allowedDecimalPlaces',
        'Must contain unique decimal places from 1 through 3.',
      );
    }

    return ArithmeticDifficultyConfig._(
      difficulty: difficulty,
      minOperandDigits: minOperandDigits,
      maxOperandDigits: maxOperandDigits,
      minAdditionOperands: minAdditionOperands,
      maxAdditionOperands: maxAdditionOperands,
      minSubtractionOperands: minSubtractionOperands,
      maxSubtractionOperands: maxSubtractionOperands,
      minMultiplicationFactorDigits: minMultiplicationFactorDigits,
      maxMultiplicationFactorDigits: maxMultiplicationFactorDigits,
      maxDivisionDivisorDigits: maxDivisionDivisorDigits,
      maxDivisionQuotientDigits: maxDivisionQuotientDigits,
      allowNegativeResults: allowNegativeResults,
      decimalProbability: decimalProbability,
      allowedDecimalPlaces: places,
      allowRepeatingDivisionResults: allowRepeatingDivisionResults,
      mixedOperationProbability: mixedOperationProbability,
      minMixedOperations: minMixedOperations,
      maxMixedOperations: maxMixedOperations,
      maxGenerationAttempts: maxGenerationAttempts,
      recentQuestionHistory: recentQuestionHistory,
    );
  }

  const ArithmeticDifficultyConfig._({
    required this.difficulty,
    required this.minOperandDigits,
    required this.maxOperandDigits,
    required this.minAdditionOperands,
    required this.maxAdditionOperands,
    required this.minSubtractionOperands,
    required this.maxSubtractionOperands,
    required this.minMultiplicationFactorDigits,
    required this.maxMultiplicationFactorDigits,
    required this.maxDivisionDivisorDigits,
    required this.maxDivisionQuotientDigits,
    required this.allowNegativeResults,
    required this.decimalProbability,
    required this.allowedDecimalPlaces,
    required this.allowRepeatingDivisionResults,
    required this.mixedOperationProbability,
    required this.minMixedOperations,
    required this.maxMixedOperations,
    required this.maxGenerationAttempts,
    required this.recentQuestionHistory,
  });

  final ArithmeticDifficulty difficulty;
  final int minOperandDigits;
  final int maxOperandDigits;
  final int minAdditionOperands;
  final int maxAdditionOperands;
  final int minSubtractionOperands;
  final int maxSubtractionOperands;
  final int minMultiplicationFactorDigits;
  final int maxMultiplicationFactorDigits;
  final int maxDivisionDivisorDigits;
  final int maxDivisionQuotientDigits;
  final bool allowNegativeResults;
  final double decimalProbability;
  final List<int> allowedDecimalPlaces;
  final bool allowRepeatingDivisionResults;
  final double mixedOperationProbability;
  final int minMixedOperations;
  final int maxMixedOperations;
  final int maxGenerationAttempts;
  final int recentQuestionHistory;

  /// Beginner defaults: mostly small whole numbers, with occasional tenths.
  static ArithmeticDifficultyConfig get beginner => ArithmeticDifficultyConfig(
    difficulty: ArithmeticDifficulty.beginner,
    minOperandDigits: 1,
    maxOperandDigits: 2,
    minAdditionOperands: 2,
    maxAdditionOperands: 3,
    minSubtractionOperands: 2,
    maxSubtractionOperands: 2,
    minMultiplicationFactorDigits: 1,
    maxMultiplicationFactorDigits: 1,
    maxDivisionDivisorDigits: 1,
    maxDivisionQuotientDigits: 1,
    decimalProbability: 0.12,
    allowedDecimalPlaces: const [1],
    mixedOperationProbability: 0.05,
    minMixedOperations: 2,
    maxMixedOperations: 2,
  );

  /// Medium defaults: more operands and two-digit factors/divisors.
  static ArithmeticDifficultyConfig get medium => ArithmeticDifficultyConfig(
    difficulty: ArithmeticDifficulty.medium,
    minOperandDigits: 1,
    maxOperandDigits: 3,
    minAdditionOperands: 2,
    maxAdditionOperands: 4,
    minSubtractionOperands: 2,
    maxSubtractionOperands: 3,
    minMultiplicationFactorDigits: 1,
    maxMultiplicationFactorDigits: 2,
    maxDivisionDivisorDigits: 2,
    maxDivisionQuotientDigits: 2,
    decimalProbability: 0.2,
    allowedDecimalPlaces: const [1, 2],
    mixedOperationProbability: 0.12,
    minMixedOperations: 2,
    maxMixedOperations: 3,
  );

  /// Advanced defaults: larger operands, optional negative results and 3-place
  /// decimals. Repeating division answers remain disabled by default.
  static ArithmeticDifficultyConfig get advanced => ArithmeticDifficultyConfig(
    difficulty: ArithmeticDifficulty.advanced,
    minOperandDigits: 2,
    maxOperandDigits: 4,
    minAdditionOperands: 3,
    maxAdditionOperands: 5,
    minSubtractionOperands: 2,
    maxSubtractionOperands: 4,
    minMultiplicationFactorDigits: 2,
    maxMultiplicationFactorDigits: 3,
    maxDivisionDivisorDigits: 3,
    maxDivisionQuotientDigits: 3,
    allowNegativeResults: true,
    decimalProbability: 0.3,
    allowedDecimalPlaces: const [1, 2, 3],
    mixedOperationProbability: 0.2,
    minMixedOperations: 3,
    maxMixedOperations: 4,
  );

  static Map<ArithmeticDifficulty, ArithmeticDifficultyConfig> get defaults =>
      Map.unmodifiable({
        ArithmeticDifficulty.beginner: beginner,
        ArithmeticDifficulty.medium: medium,
        ArithmeticDifficulty.advanced: advanced,
      });

  static void _validateDigitRange(int min, int max, String name) {
    if (min < 1 || max < min || max > 6) {
      throw ArgumentError('$name digit limits must be between 1 and 6.');
    }
  }

  static void _validateCountRange(int min, int max, String name) {
    if (min < 2 || max < min || max > 6) {
      throw ArgumentError('$name count must be between 2 and 6.');
    }
  }

  static void _validateProbability(double probability, String name) {
    if (!probability.isFinite || probability < 0 || probability > 1) {
      throw ArgumentError.value(probability, name, 'Must be from 0.0 to 1.0.');
    }
  }
}
