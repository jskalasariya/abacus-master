import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:abacus_master/domain/arithmetic/arithmetic_operation.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_question.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_question_generator.dart';
import 'package:abacus_master/domain/arithmetic/multiple_choice_option_generator.dart';
import 'package:abacus_master/domain/arithmetic/rational.dart';

void main() {
  test('creates four distinct options and exactly one correct choice', () {
    final questions = ArithmeticQuestionGenerator(seed: 7001);
    final choices = MultipleChoiceOptionGenerator(seed: 7002);
    for (final level in ArithmeticDifficulty.values) {
      for (final operation in ArithmeticOperation.values) {
        final question = questions.generateQuestion(
          difficulty: level,
          operation: operation,
        );
        final options = choices.generate(question);

        expect(options, hasLength(4));
        expect(options.where((option) => option.isCorrect), hasLength(1));
        expect(
          options.where((option) => option.value == question.correctAnswer),
          hasLength(1),
        );
        expect(options.map((option) => option.value).toSet(), hasLength(4));
        expect(
          options.map((option) => _displayValue(option.text)).toSet(),
          hasLength(4),
        );
        expect(
          options.singleWhere((option) => option.isCorrect).text,
          question.formattedAnswer,
        );
      }
    }
  });

  test('rounded options never repeat an equivalent displayed value', () {
    final question = ArithmeticQuestion(
      expression: '1 / 100',
      operation: ArithmeticOperation.division,
      correctAnswer: Rational(BigInt.one, BigInt.from(100)),
      difficulty: ArithmeticDifficulty.beginner,
      decimalPrecision: 1,
    );
    final options = MultipleChoiceOptionGenerator(seed: 42).generate(question);

    expect(options, hasLength(4));
    expect(
      options.map((option) => _displayValue(option.text)).toSet(),
      hasLength(4),
    );
    expect(options.singleWhere((option) => option.isCorrect).text, '≈ 0.0');
  });

  test('correct answer positions are shuffled across repeated questions', () {
    final questions = ArithmeticQuestionGenerator(seed: 1729);
    final choices = MultipleChoiceOptionGenerator(seed: 2718);
    final positions = <int>{};
    for (var i = 0; i < 400; i++) {
      final question = questions.generateQuestion(
        difficulty: ArithmeticDifficulty.medium,
        operation: ArithmeticOperation.addition,
      );
      final options = choices.generate(question);
      positions.add(options.indexWhere((option) => option.isCorrect));
    }
    expect(positions, hasLength(4));
  });

  test('same random seed reproduces question and option sequences', () {
    final questionA = ArithmeticQuestionGenerator(seed: 311);
    final questionB = ArithmeticQuestionGenerator(seed: 311);
    final choicesA = MultipleChoiceOptionGenerator(seed: 919);
    final choicesB = MultipleChoiceOptionGenerator(seed: 919);

    for (var i = 0; i < 100; i++) {
      final level = ArithmeticDifficulty.values[i % 3];
      final operation = ArithmeticOperation.values[i % 4];
      final firstQuestion = questionA.generateQuestion(
        difficulty: level,
        operation: operation,
      );
      final secondQuestion = questionB.generateQuestion(
        difficulty: level,
        operation: operation,
      );
      expect(firstQuestion.expression, secondQuestion.expression);
      final firstOptions = choicesA.generate(firstQuestion);
      final secondOptions = choicesB.generate(secondQuestion);
      expect(
        firstOptions.map((option) => '${option.text}:${option.isCorrect}'),
        secondOptions.map((option) => '${option.text}:${option.isCorrect}'),
      );
    }
  });

  test(
    'bounded fallback fills options when candidate attempts are restricted',
    () {
      final question = ArithmeticQuestion(
        expression: '0.01 + 0',
        operation: ArithmeticOperation.addition,
        correctAnswer: Rational(BigInt.one, BigInt.from(100)),
        difficulty: ArithmeticDifficulty.beginner,
        decimalPrecision: 2,
      );
      final generator = MultipleChoiceOptionGenerator(
        random: Random(5),
        config: OptionGenerationConfig(
          maxCandidateAttempts: 1,
          maxFallbackSteps: 2,
        ),
      );

      final options = generator.generate(question);
      expect(options, hasLength(4));
      expect(options.where((option) => option.isCorrect), hasLength(1));
    },
  );

  test('rejects invalid option-generation bounds', () {
    expect(
      () => OptionGenerationConfig(maxCandidateAttempts: 0),
      throwsArgumentError,
    );
    expect(
      () => OptionGenerationConfig(maxFallbackSteps: 1),
      throwsArgumentError,
    );
    expect(
      () => OptionGenerationConfig(nearbyStepMultipliers: const []),
      throwsArgumentError,
    );
  });
}

Rational _displayValue(String text) {
  final withoutApproximation = text.startsWith('≈ ') ? text.substring(2) : text;
  final fractionParts = withoutApproximation.split('/');
  if (fractionParts.length == 2) {
    return Rational(
      BigInt.parse(fractionParts[0]),
      BigInt.parse(fractionParts[1]),
    );
  }
  return Rational.fromDecimal(withoutApproximation);
}
