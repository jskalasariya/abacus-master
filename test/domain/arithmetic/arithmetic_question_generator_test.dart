import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:abacus_master/domain/arithmetic/arithmetic_difficulty_config.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_operation.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_question_generator.dart';
import 'package:abacus_master/domain/arithmetic/calculation_service.dart';
import 'package:abacus_master/domain/arithmetic/rational.dart';

void main() {
  const calculator = CalculationService();
  final levels = ArithmeticDifficulty.values;
  final operations = ArithmeticOperation.values;

  test('all four operations generate valid questions at each difficulty', () {
    final generator = ArithmeticQuestionGenerator(seed: 18031);
    for (final level in levels) {
      final config = ArithmeticDifficultyConfig.defaults[level]!;
      for (final operation in operations) {
        for (var i = 0; i < 40; i++) {
          final question = generator.generateQuestion(
            difficulty: level,
            operation: operation,
          );
          expect(question.difficulty, level);
          expect(question.operation, operation);
          expect(
            calculator.evaluate(question.expression),
            question.correctAnswer,
          );
          if (!config.allowNegativeResults) {
            expect(question.correctAnswer.numerator.isNegative, isFalse);
          }
          if (operation == ArithmeticOperation.division) {
            expect(_isTerminating(question.correctAnswer), isTrue);
          }
        }
      }
    }
  });

  test('generates decimal operands at 1, 2 and 3 places for each level', () {
    for (final level in levels) {
      for (final places in [1, 2, 3]) {
        final generator = ArithmeticQuestionGenerator(
          seed: 500 + places,
          configurations: _configs(
            decimalProbability: 1,
            allowedDecimalPlaces: [places],
          ),
        );
        for (final operation in operations) {
          final question = generator.generateQuestion(
            difficulty: level,
            operation: operation,
          );
          expect(question.decimalPrecision, places);
          expect(question.expression, contains('.'));
          expect(
            calculator.evaluate(question.expression),
            question.correctAnswer,
          );
          if (operation == ArithmeticOperation.division) {
            expect(_isTerminating(question.correctAnswer), isTrue);
          }
        }
      }
    }
  });

  test('default division answers remain finite decimals', () {
    final generator = ArithmeticQuestionGenerator(seed: 723);
    for (final level in levels) {
      for (var i = 0; i < 250; i++) {
        final question = generator.generateQuestion(
          difficulty: level,
          operation: ArithmeticOperation.division,
        );
        expect(question.correctAnswer.isZero, isFalse);
        expect(_isTerminating(question.correctAnswer), isTrue);
      }
    }
  });

  test('operand counts and operation-specific digit limits are respected', () {
    final generator = ArithmeticQuestionGenerator(seed: 318);
    for (final level in levels) {
      final config = ArithmeticDifficultyConfig.defaults[level]!;
      for (var i = 0; i < 80; i++) {
        final addition = generator.generateQuestion(
          difficulty: level,
          operation: ArithmeticOperation.addition,
        );
        final additionOperands = _expressionOperands(addition.expression);
        expect(
          additionOperands.length,
          inInclusiveRange(
            config.minAdditionOperands,
            config.maxAdditionOperands,
          ),
        );
        for (final operand in additionOperands) {
          expect(
            _wholeDigits(operand),
            inInclusiveRange(config.minOperandDigits, config.maxOperandDigits),
          );
        }

        final subtraction = generator.generateQuestion(
          difficulty: level,
          operation: ArithmeticOperation.subtraction,
        );
        expect(
          _expressionOperands(subtraction.expression).length,
          inInclusiveRange(
            config.minSubtractionOperands,
            config.maxSubtractionOperands,
          ),
        );

        final multiplication = generator.generateQuestion(
          difficulty: level,
          operation: ArithmeticOperation.multiplication,
        );
        final factors = _expressionOperands(multiplication.expression);
        expect(factors, hasLength(2));
        for (final factor in factors) {
          expect(
            _wholeDigits(factor),
            inInclusiveRange(
              config.minMultiplicationFactorDigits,
              config.maxMultiplicationFactorDigits,
            ),
          );
        }

        final division = generator.generateQuestion(
          difficulty: level,
          operation: ArithmeticOperation.division,
        );
        final divisor = _expressionOperands(division.expression).last;
        expect(
          _wholeDigits(divisor),
          lessThanOrEqualTo(config.maxDivisionDivisorDigits),
        );
        expect(division.correctAnswer.denominator, BigInt.one);
        expect(
          _wholeDigits(division.correctAnswer),
          lessThanOrEqualTo(config.maxDivisionQuotientDigits),
        );
      }
    }
  });

  test('repeating division answers are possible only when enabled', () {
    final exactGenerator = ArithmeticQuestionGenerator(seed: 902);
    final repeatingGenerator = ArithmeticQuestionGenerator(
      seed: 902,
      configurations: _configs(
        allowRepeatingDivisionResults: true,
        decimalProbability: 0,
      ),
    );

    expect(
      List.generate(
        100,
        (_) => exactGenerator.generateQuestion(
          difficulty: ArithmeticDifficulty.beginner,
          operation: ArithmeticOperation.division,
        ),
      ).every((question) => _isTerminating(question.correctAnswer)),
      isTrue,
    );
    final repeatingQuestions = List.generate(
      100,
      (_) => repeatingGenerator.generateQuestion(
        difficulty: ArithmeticDifficulty.beginner,
        operation: ArithmeticOperation.division,
      ),
    );
    expect(
      repeatingQuestions.any(
        (question) => !_isTerminating(question.correctAnswer),
      ),
      isTrue,
    );
  });

  test('respects negative-result policy and can create advanced negatives', () {
    final generator = ArithmeticQuestionGenerator(seed: 4219);
    for (final level in [
      ArithmeticDifficulty.beginner,
      ArithmeticDifficulty.medium,
    ]) {
      for (var i = 0; i < 120; i++) {
        final question = generator.generateQuestion(
          difficulty: level,
          operation: ArithmeticOperation.subtraction,
        );
        expect(question.correctAnswer.numerator.isNegative, isFalse);
      }
    }

    final advancedQuestions = List.generate(
      100,
      (_) => generator.generateQuestion(
        difficulty: ArithmeticDifficulty.advanced,
        operation: ArithmeticOperation.subtraction,
      ),
    );
    expect(
      advancedQuestions.any(
        (question) => question.correctAnswer.numerator.isNegative,
      ),
      isTrue,
    );
  });

  test('mixed questions contain multiple operations and evaluate exactly', () {
    final generator = ArithmeticQuestionGenerator(seed: 1057);
    for (final level in levels) {
      for (var i = 0; i < 30; i++) {
        final question = generator.generateMixedQuestion(difficulty: level);
        final operators = RegExp(r' [-+*/] ')
            .allMatches(question.expression)
            .map((match) => match.group(0)!.trim())
            .toSet();
        expect(operators.length, greaterThanOrEqualTo(2));
        expect(
          calculator.evaluate(question.expression),
          question.correctAnswer,
        );
      }
    }
  });

  test('same seed reproduces generated expressions and answers', () {
    final first = ArithmeticQuestionGenerator(seed: 9182);
    final second = ArithmeticQuestionGenerator(seed: 9182);
    for (var i = 0; i < 100; i++) {
      final difficulty = levels[i % levels.length];
      final questionA = first.generateQuestion(difficulty: difficulty);
      final questionB = second.generateQuestion(difficulty: difficulty);
      expect(questionA.expression, questionB.expression);
      expect(questionA.correctAnswer, questionB.correctAnswer);
      expect(questionA.decimalPrecision, questionB.decimalPrecision);
    }
  });

  test('bounded fallback terminates with difficult narrow constraints', () {
    final constrained = ArithmeticQuestionGenerator(
      random: Random(29),
      configurations: _configs(
        minOperandDigits: 1,
        maxOperandDigits: 1,
        minAdditionOperands: 2,
        maxAdditionOperands: 2,
        minSubtractionOperands: 2,
        maxSubtractionOperands: 6,
        decimalProbability: 0,
        maxGenerationAttempts: 1,
        recentQuestionHistory: 1000,
      ),
    );
    for (var i = 0; i < 100; i++) {
      final question = constrained.generateQuestion(
        difficulty: ArithmeticDifficulty.beginner,
        operation: ArithmeticOperation.subtraction,
      );
      expect(question.correctAnswer.numerator.isNegative, isFalse);
      expect(calculator.evaluate(question.expression), question.correctAnswer);
    }
  });

  test('validates 10,000 generated questions across levels and operations', () {
    final generator = ArithmeticQuestionGenerator(seed: 816284);
    for (var i = 0; i < 10000; i++) {
      final level = levels[i % levels.length];
      final operation = operations[(i ~/ levels.length) % operations.length];
      final question = generator.generateQuestion(
        difficulty: level,
        operation: operation,
      );
      if (calculator.evaluate(question.expression) != question.correctAnswer ||
          question.operation != operation ||
          question.difficulty != level ||
          (!ArithmeticDifficultyConfig.defaults[level]!.allowNegativeResults &&
              question.correctAnswer.numerator.isNegative) ||
          (operation == ArithmeticOperation.division &&
              !_isTerminating(question.correctAnswer))) {
        fail('Generated question $i failed validation: ${question.expression}');
      }
    }
  });

  test('rejects invalid configuration values', () {
    expect(
      () => ArithmeticDifficultyConfig(
        difficulty: ArithmeticDifficulty.beginner,
        minOperandDigits: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ArithmeticDifficultyConfig(
        difficulty: ArithmeticDifficulty.beginner,
        decimalProbability: 1.1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ArithmeticDifficultyConfig(
        difficulty: ArithmeticDifficulty.beginner,
        allowedDecimalPlaces: const [1, 1],
      ),
      throwsArgumentError,
    );
  });
}

Map<ArithmeticDifficulty, ArithmeticDifficultyConfig> _configs({
  int? minOperandDigits,
  int? maxOperandDigits,
  int? minAdditionOperands,
  int? maxAdditionOperands,
  int? minSubtractionOperands,
  int? maxSubtractionOperands,
  double? decimalProbability,
  Iterable<int>? allowedDecimalPlaces,
  bool? allowRepeatingDivisionResults,
  bool? allowNegativeResults,
  int? maxGenerationAttempts,
  int? recentQuestionHistory,
}) => {
  for (final level in ArithmeticDifficulty.values)
    level: _copyConfig(
      ArithmeticDifficultyConfig.defaults[level]!,
      minOperandDigits: minOperandDigits,
      maxOperandDigits: maxOperandDigits,
      minAdditionOperands: minAdditionOperands,
      maxAdditionOperands: maxAdditionOperands,
      minSubtractionOperands: minSubtractionOperands,
      maxSubtractionOperands: maxSubtractionOperands,
      decimalProbability: decimalProbability,
      allowedDecimalPlaces: allowedDecimalPlaces,
      allowRepeatingDivisionResults: allowRepeatingDivisionResults,
      allowNegativeResults: allowNegativeResults,
      maxGenerationAttempts: maxGenerationAttempts,
      recentQuestionHistory: recentQuestionHistory,
    ),
};

ArithmeticDifficultyConfig _copyConfig(
  ArithmeticDifficultyConfig source, {
  int? minOperandDigits,
  int? maxOperandDigits,
  int? minAdditionOperands,
  int? maxAdditionOperands,
  int? minSubtractionOperands,
  int? maxSubtractionOperands,
  double? decimalProbability,
  Iterable<int>? allowedDecimalPlaces,
  bool? allowRepeatingDivisionResults,
  bool? allowNegativeResults,
  int? maxGenerationAttempts,
  int? recentQuestionHistory,
}) => ArithmeticDifficultyConfig(
  difficulty: source.difficulty,
  minOperandDigits: minOperandDigits ?? source.minOperandDigits,
  maxOperandDigits: maxOperandDigits ?? source.maxOperandDigits,
  minAdditionOperands: minAdditionOperands ?? source.minAdditionOperands,
  maxAdditionOperands: maxAdditionOperands ?? source.maxAdditionOperands,
  minSubtractionOperands:
      minSubtractionOperands ?? source.minSubtractionOperands,
  maxSubtractionOperands:
      maxSubtractionOperands ?? source.maxSubtractionOperands,
  minMultiplicationFactorDigits: source.minMultiplicationFactorDigits,
  maxMultiplicationFactorDigits: source.maxMultiplicationFactorDigits,
  maxDivisionDivisorDigits: source.maxDivisionDivisorDigits,
  maxDivisionQuotientDigits: source.maxDivisionQuotientDigits,
  allowNegativeResults: allowNegativeResults ?? source.allowNegativeResults,
  decimalProbability: decimalProbability ?? source.decimalProbability,
  allowedDecimalPlaces: allowedDecimalPlaces ?? source.allowedDecimalPlaces,
  allowRepeatingDivisionResults:
      allowRepeatingDivisionResults ?? source.allowRepeatingDivisionResults,
  mixedOperationProbability: source.mixedOperationProbability,
  minMixedOperations: source.minMixedOperations,
  maxMixedOperations: source.maxMixedOperations,
  maxGenerationAttempts: maxGenerationAttempts ?? source.maxGenerationAttempts,
  recentQuestionHistory: recentQuestionHistory ?? source.recentQuestionHistory,
);

bool _isTerminating(Rational value) {
  var denominator = value.denominator;
  for (final factor in [BigInt.two, BigInt.from(5)]) {
    while (denominator % factor == BigInt.zero) {
      denominator ~/= factor;
    }
  }
  return denominator == BigInt.one;
}

List<Rational> _expressionOperands(String expression) =>
    RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(expression)
        .map((match) => Rational.fromDecimal(match.group(0)!))
        .toList();

int _wholeDigits(Rational value) {
  final whole = value.numerator.abs() ~/ value.denominator;
  return whole.toString().length;
}
