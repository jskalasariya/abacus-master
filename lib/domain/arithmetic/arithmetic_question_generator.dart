import 'dart:math';

import 'arithmetic_difficulty_config.dart';
import 'arithmetic_operation.dart';
import 'arithmetic_question.dart';
import 'calculation_service.dart';
import 'rational.dart';

/// Creates bounded, difficulty-aware arithmetic questions.
///
/// Pass a seeded [Random] for reproducible sessions and tests. Generation is
/// intentionally separate from evaluation: this class builds expression text
/// and delegates the answer and root-operation calculation to
/// [CalculationService]. Mixed expressions combine addition, subtraction and
/// multiplication; division remains a standalone operation so the default
/// exact-division rule is simple to guarantee.
final class ArithmeticQuestionGenerator {
  ArithmeticQuestionGenerator({
    Random? random,
    int? seed,
    this.calculationService = const CalculationService(),
    Map<ArithmeticDifficulty, ArithmeticDifficultyConfig>? configurations,
  }) : _random = _makeRandom(random, seed),
       _configurations = _validatedConfigurations(configurations);

  final Random _random;
  final CalculationService calculationService;
  final Map<ArithmeticDifficulty, ArithmeticDifficultyConfig> _configurations;
  final Map<ArithmeticDifficulty, List<String>> _recentExpressions = {};

  /// Generates one of the four single-operation questions, or a mixed
  /// question according to the selected configuration's probability.
  ArithmeticQuestion generateQuestion({
    required ArithmeticDifficulty difficulty,
    ArithmeticOperation? operation,
  }) {
    final config = _configurations[difficulty]!;
    if (operation == null &&
        _random.nextDouble() < config.mixedOperationProbability) {
      return generateMixedQuestion(difficulty: difficulty);
    }
    final selectedOperation =
        operation ??
        ArithmeticOperation.values[_random.nextInt(
          ArithmeticOperation.values.length,
        )];
    return _generate(difficulty, config, operation: selectedOperation);
  }

  /// Generates a mixed expression from addition, subtraction and
  /// multiplication. The configured operator count controls its complexity.
  ArithmeticQuestion generateMixedQuestion({
    required ArithmeticDifficulty difficulty,
  }) {
    final config = _configurations[difficulty]!;
    return _generate(difficulty, config, mixed: true);
  }

  ArithmeticQuestion _generate(
    ArithmeticDifficulty difficulty,
    ArithmeticDifficultyConfig config, {
    ArithmeticOperation? operation,
    bool mixed = false,
  }) {
    for (var attempt = 0; attempt < config.maxGenerationAttempts; attempt++) {
      final decimalPlaces = _chooseDecimalPlaces(config);
      final expression = mixed
          ? _mixedExpression(config, decimalPlaces)
          : _singleOperationExpression(operation!, config, decimalPlaces);
      final question = calculationService.questionFromExpression(
        expression: expression,
        difficulty: difficulty,
        decimalPrecision: decimalPlaces,
      );

      if (!_isAcceptable(question, config) ||
          _isRecent(difficulty, expression, config.recentQuestionHistory)) {
        continue;
      }
      _remember(difficulty, expression, config.recentQuestionHistory);
      return question;
    }

    // Deterministic fallback guarantees bounded termination even for narrow
    // custom configurations or a saturated recent-question history.
    final decimalPlaces = _chooseDecimalPlaces(config);
    final expression = mixed
        ? _fallbackMixedExpression(config, decimalPlaces)
        : _fallbackSingleExpression(operation!, config, decimalPlaces);
    final fallback = calculationService.questionFromExpression(
      expression: expression,
      difficulty: difficulty,
      decimalPrecision: decimalPlaces,
    );
    if (!_isAcceptable(fallback, config)) {
      throw StateError('The configured question fallback was not acceptable.');
    }
    _remember(difficulty, expression, config.recentQuestionHistory);
    return fallback;
  }

  String _singleOperationExpression(
    ArithmeticOperation operation,
    ArithmeticDifficultyConfig config,
    int? decimalPlaces,
  ) {
    switch (operation) {
      case ArithmeticOperation.addition:
        final count = _randomInRange(
          config.minAdditionOperands,
          config.maxAdditionOperands,
        );
        final operands = List.generate(
          count,
          (_) => _randomOperand(
            config.minOperandDigits,
            config.maxOperandDigits,
            decimalPlaces,
            allowNegative: config.allowNegativeResults,
          ),
        );
        return operands.map((operand) => '(${operand.text})').join(' + ');
      case ArithmeticOperation.subtraction:
        final count = _randomInRange(
          config.minSubtractionOperands,
          config.maxSubtractionOperands,
        );
        final operands = List.generate(
          count,
          (_) => _randomOperand(
            config.minOperandDigits,
            config.maxOperandDigits,
            decimalPlaces,
            allowNegative: config.allowNegativeResults,
          ),
        );
        return operands.map((operand) => '(${operand.text})').join(' - ');
      case ArithmeticOperation.multiplication:
        final left = _randomOperand(
          config.minMultiplicationFactorDigits,
          config.maxMultiplicationFactorDigits,
          decimalPlaces,
          allowNegative: config.allowNegativeResults,
          minimumOneDigitValue: 2,
        );
        final right = _randomOperand(
          config.minMultiplicationFactorDigits,
          config.maxMultiplicationFactorDigits,
          decimalPlaces,
          allowNegative: config.allowNegativeResults,
          minimumOneDigitValue: 2,
        );
        return '(${left.text}) * (${right.text})';
      case ArithmeticOperation.division:
        return _divisionExpression(config, decimalPlaces);
    }
  }

  String _divisionExpression(
    ArithmeticDifficultyConfig config,
    int? decimalPlaces,
  ) {
    if (config.allowRepeatingDivisionResults) {
      final dividend = _randomOperand(
        config.minOperandDigits,
        config.maxOperandDigits,
        decimalPlaces,
        allowNegative: config.allowNegativeResults,
      );
      final divisor = _randomOperand(
        1,
        config.maxDivisionDivisorDigits,
        decimalPlaces,
        allowNegative: false,
        minimumOneDigitValue: 2,
      );
      return '(${dividend.text}) / (${divisor.text})';
    }

    // Build dividend as divisor × a nonzero integer quotient. The expression
    // is still evaluated by CalculationService; this construction guarantees
    // exact division without relying on floating-point divisibility checks.
    final divisor = _randomOperand(
      1,
      config.maxDivisionDivisorDigits,
      decimalPlaces,
      allowNegative: false,
      minimumOneDigitValue: 2,
    );
    final quotient = _randomOperand(
      1,
      config.maxDivisionQuotientDigits,
      null,
      allowNegative: false,
      minimumOneDigitValue: 2,
    );
    var dividendValue = divisor.value * quotient.value;
    if (config.allowNegativeResults && _random.nextBool()) {
      dividendValue = -dividendValue;
    }
    final dividendText = _formatOperand(dividendValue, decimalPlaces);
    return '($dividendText) / (${divisor.text})';
  }

  String _mixedExpression(
    ArithmeticDifficultyConfig config,
    int? decimalPlaces,
  ) {
    final count = _randomInRange(
      config.minMixedOperations,
      config.maxMixedOperations,
    );
    final supported = [
      ArithmeticOperation.addition,
      ArithmeticOperation.subtraction,
      ArithmeticOperation.multiplication,
    ];
    final operators = <ArithmeticOperation>[
      supported[_random.nextInt(supported.length)],
    ];
    final secondChoices = supported
        .where((candidate) => candidate != operators.first)
        .toList();
    operators.add(secondChoices[_random.nextInt(secondChoices.length)]);
    while (operators.length < count) {
      operators.add(supported[_random.nextInt(supported.length)]);
    }

    final operands = List.generate(
      count + 1,
      (_) => _randomOperand(
        config.minOperandDigits,
        config.maxOperandDigits,
        decimalPlaces,
        allowNegative: config.allowNegativeResults,
      ),
    );
    final buffer = StringBuffer('(${operands.first.text})');
    for (var i = 0; i < count; i++) {
      buffer
        ..write(' ${operators[i].symbol} ')
        ..write('(${operands[i + 1].text})');
    }
    return buffer.toString();
  }

  int? _chooseDecimalPlaces(ArithmeticDifficultyConfig config) {
    if (_random.nextDouble() >= config.decimalProbability) return null;
    return config.allowedDecimalPlaces[_random.nextInt(
      config.allowedDecimalPlaces.length,
    )];
  }

  _GeneratedOperand _randomOperand(
    int minDigits,
    int maxDigits,
    int? decimalPlaces, {
    required bool allowNegative,
    int minimumOneDigitValue = 1,
  }) {
    final digitCount = _randomInRange(minDigits, maxDigits);
    var minimumWhole = _powerOfTen(digitCount - 1);
    if (digitCount == 1 && minimumWhole < minimumOneDigitValue) {
      minimumWhole = minimumOneDigitValue;
    }
    final maximumWhole = _powerOfTen(digitCount) - 1;
    final whole =
        minimumWhole + _random.nextInt(maximumWhole - minimumWhole + 1);
    final scale = decimalPlaces == null ? 1 : _powerOfTen(decimalPlaces);
    final fraction = decimalPlaces == null ? 0 : 1 + _random.nextInt(scale - 1);
    final units = whole * scale + fraction;
    var value = Rational(BigInt.from(units), BigInt.from(scale));
    if (allowNegative && _random.nextBool()) value = -value;
    return _GeneratedOperand(value, _formatOperand(value, decimalPlaces));
  }

  String _fallbackSingleExpression(
    ArithmeticOperation operation,
    ArithmeticDifficultyConfig config,
    int? decimalPlaces,
  ) {
    final scale = decimalPlaces == null ? 1 : _powerOfTen(decimalPlaces);
    final minimum = _powerOfTen(config.minOperandDigits - 1);
    final lowUnits = minimum * scale + (decimalPlaces == null ? 0 : 1);
    final low = Rational(BigInt.from(lowUnits), BigInt.from(scale));
    final lowText = _formatOperand(low, decimalPlaces);
    final slightlyHigher = low + Rational(BigInt.one, BigInt.from(scale));
    final higherText = _formatOperand(slightlyHigher, decimalPlaces);

    switch (operation) {
      case ArithmeticOperation.addition:
        final count = config.minAdditionOperands;
        final operands = List.generate(
          count,
          (index) => index == 1 ? higherText : lowText,
        );
        return operands.map((text) => '($text)').join(' + ');
      case ArithmeticOperation.subtraction:
        final count = config.minSubtractionOperands;
        final maximumWhole = _powerOfTen(config.maxOperandDigits) - 1;
        final highUnits =
            maximumWhole * scale + (decimalPlaces == null ? 0 : scale - 1);
        final highText = _formatOperand(
          Rational(BigInt.from(highUnits), BigInt.from(scale)),
          decimalPlaces,
        );
        final operands = [highText, ...List.filled(count - 1, lowText)];
        return operands.map((text) => '($text)').join(' - ');
      case ArithmeticOperation.multiplication:
        final factorMinimum = _powerOfTen(
          config.minMultiplicationFactorDigits - 1,
        );
        final factor = factorMinimum < 2 ? 2 : factorMinimum;
        final factorValue = Rational(
          BigInt.from(factor * scale + (decimalPlaces == null ? 0 : 1)),
          BigInt.from(scale),
        );
        final nextValue = factorValue + Rational.fromInt(1);
        return '(${_formatOperand(factorValue, decimalPlaces)}) * '
            '(${_formatOperand(nextValue, decimalPlaces)})';
      case ArithmeticOperation.division:
        final divisorMinimum = _powerOfTen(config.maxDivisionDivisorDigits - 1);
        final divisorWhole = divisorMinimum < 2 ? 2 : divisorMinimum;
        final divisor = Rational(
          BigInt.from(divisorWhole * scale + (decimalPlaces == null ? 0 : 1)),
          BigInt.from(scale),
        );
        final quotient = Rational.fromInt(2);
        final dividend = divisor * quotient;
        return '(${_formatOperand(dividend, decimalPlaces)}) / '
            '(${_formatOperand(divisor, decimalPlaces)})';
    }
  }

  String _fallbackMixedExpression(
    ArithmeticDifficultyConfig config,
    int? decimalPlaces,
  ) {
    final count = config.minMixedOperations;
    final scale = decimalPlaces == null ? 1 : _powerOfTen(decimalPlaces);
    final baseWhole = _powerOfTen(config.minOperandDigits - 1);
    final operands = List.generate(count + 1, (index) {
      final units =
          (baseWhole + index) * scale + (decimalPlaces == null ? 0 : 1);
      return _formatOperand(
        Rational(BigInt.from(units), BigInt.from(scale)),
        decimalPlaces,
      );
    });
    const operators = [
      ArithmeticOperation.addition,
      ArithmeticOperation.multiplication,
      ArithmeticOperation.subtraction,
      ArithmeticOperation.addition,
      ArithmeticOperation.multiplication,
      ArithmeticOperation.subtraction,
    ];
    final buffer = StringBuffer('(${operands.first})');
    for (var index = 0; index < count; index++) {
      buffer
        ..write(' ${operators[index].symbol} ')
        ..write('(${operands[index + 1]})');
    }
    return buffer.toString();
  }

  bool _isAcceptable(
    ArithmeticQuestion question,
    ArithmeticDifficultyConfig config,
  ) {
    if (question.correctAnswer.isZero) return false;
    return config.allowNegativeResults ||
        !question.correctAnswer.numerator.isNegative;
  }

  bool _isRecent(
    ArithmeticDifficulty difficulty,
    String expression,
    int historyLimit,
  ) {
    if (historyLimit == 0) return false;
    return _recentExpressions[difficulty]?.contains(expression) ?? false;
  }

  void _remember(
    ArithmeticDifficulty difficulty,
    String expression,
    int historyLimit,
  ) {
    if (historyLimit == 0) return;
    final history = _recentExpressions.putIfAbsent(difficulty, () => []);
    history.add(expression);
    if (history.length > historyLimit) {
      history.removeAt(0);
    }
  }

  int _randomInRange(int min, int max) => min + _random.nextInt(max - min + 1);

  static int _powerOfTen(int exponent) {
    var value = 1;
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
    return value;
  }

  static String _formatOperand(Rational value, int? decimalPlaces) {
    return value.formatForDisplay(decimalPlaces: decimalPlaces);
  }

  static Random _makeRandom(Random? random, int? seed) {
    if (random != null && seed != null) {
      throw ArgumentError('Provide either random or seed, not both.');
    }
    return random ?? Random(seed);
  }

  static Map<ArithmeticDifficulty, ArithmeticDifficultyConfig>
  _validatedConfigurations(
    Map<ArithmeticDifficulty, ArithmeticDifficultyConfig>? configurations,
  ) {
    final selected = configurations ?? ArithmeticDifficultyConfig.defaults;
    for (final difficulty in ArithmeticDifficulty.values) {
      final config = selected[difficulty];
      if (config == null || config.difficulty != difficulty) {
        throw ArgumentError(
          'A matching configuration is required for $difficulty.',
        );
      }
    }
    if (selected.length != ArithmeticDifficulty.values.length) {
      throw ArgumentError(
        'Configurations must contain exactly the three levels.',
      );
    }
    return Map.unmodifiable(selected);
  }
}

class _GeneratedOperand {
  const _GeneratedOperand(this.value, this.text);

  final Rational value;
  final String text;
}
