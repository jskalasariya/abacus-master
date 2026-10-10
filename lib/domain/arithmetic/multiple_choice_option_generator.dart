import 'dart:math';

import 'arithmetic_operation.dart';
import 'arithmetic_question.dart';
import 'rational.dart';

/// Bounds the candidate and deterministic fallback work for option creation.
final class OptionGenerationConfig {
  factory OptionGenerationConfig({
    int maxCandidateAttempts = 32,
    int maxFallbackSteps = 8,
    Iterable<int> nearbyStepMultipliers = const [1, 2, 5],
    bool includeOperationMistakes = true,
  }) {
    if (maxCandidateAttempts < 1) {
      throw ArgumentError.value(
        maxCandidateAttempts,
        'maxCandidateAttempts',
        'Must be positive.',
      );
    }
    if (maxFallbackSteps < 2) {
      throw ArgumentError.value(
        maxFallbackSteps,
        'maxFallbackSteps',
        'Must be at least two.',
      );
    }
    final multipliers = List<int>.unmodifiable(nearbyStepMultipliers);
    if (multipliers.isEmpty ||
        multipliers.any((multiplier) => multiplier <= 0) ||
        multipliers.toSet().length != multipliers.length) {
      throw ArgumentError.value(
        multipliers,
        'nearbyStepMultipliers',
        'Must contain unique positive integers.',
      );
    }
    return OptionGenerationConfig._(
      maxCandidateAttempts,
      maxFallbackSteps,
      multipliers,
      includeOperationMistakes,
    );
  }

  const OptionGenerationConfig._(
    this.maxCandidateAttempts,
    this.maxFallbackSteps,
    this.nearbyStepMultipliers,
    this.includeOperationMistakes,
  );

  static final standard = OptionGenerationConfig();

  final int maxCandidateAttempts;
  final int maxFallbackSteps;
  final List<int> nearbyStepMultipliers;
  final bool includeOperationMistakes;
}

/// A single exact answer choice. [text] follows the question's display policy.
final class ArithmeticAnswerOption {
  const ArithmeticAnswerOption({
    required this.value,
    required this.text,
    required this.isCorrect,
  });

  final Rational value;
  final String text;
  final bool isCorrect;
}

/// Produces four unique, shuffled choices with exactly one correct value.
///
/// Randomness is injectable for deterministic tests. Candidate errors use
/// operation-specific patterns first, followed by bounded nearby-value
/// fallbacks. Equality is checked on exact [Rational] values and on rounded
/// display values so that equivalent choices cannot appear twice.
final class MultipleChoiceOptionGenerator {
  MultipleChoiceOptionGenerator({
    Random? random,
    int? seed,
    OptionGenerationConfig? config,
  }) : _random = _makeRandom(random, seed),
       config = config ?? OptionGenerationConfig.standard;

  final Random _random;
  final OptionGenerationConfig config;

  List<ArithmeticAnswerOption> generate(ArithmeticQuestion question) {
    final correct = question.correctAnswer;
    final options = <ArithmeticAnswerOption>[
      ArithmeticAnswerOption(
        value: correct,
        text: _format(correct, question),
        isCorrect: true,
      ),
    ];
    final exactValues = <Rational>{correct};
    final displayValues = <Rational>{_displayValue(correct, question)};
    final candidates = _distractorCandidates(question)..shuffle(_random);
    var attempts = 0;

    for (final candidate in candidates) {
      if (options.length == 4 || attempts >= config.maxCandidateAttempts) {
        break;
      }
      attempts++;
      _tryAdd(candidate, question, options, exactValues, displayValues);
    }

    final precision = question.decimalPrecision ?? 0;
    final step = Rational(BigInt.one, BigInt.from(10).pow(precision));
    for (
      var multiple = 1;
      options.length < 4 && multiple <= config.maxFallbackSteps;
      multiple++
    ) {
      final offset = step * Rational.fromInt(multiple);
      _tryAdd(correct + offset, question, options, exactValues, displayValues);
      if (options.length < 4) {
        _tryAdd(
          correct - offset,
          question,
          options,
          exactValues,
          displayValues,
        );
      }
    }

    if (options.length != 4) {
      throw StateError('Could not create four distinct answer options.');
    }
    options.shuffle(_random);
    return List.unmodifiable(options);
  }

  List<Rational> _distractorCandidates(ArithmeticQuestion question) {
    final answer = question.correctAnswer;
    final places = question.decimalPrecision ?? 0;
    final step = Rational(BigInt.one, BigInt.from(10).pow(places));
    final candidates = <Rational>[];
    for (final multiplier in config.nearbyStepMultipliers) {
      final offset = step * Rational.fromInt(multiplier);
      candidates
        ..add(answer + offset)
        ..add(answer - offset);
    }

    if (!config.includeOperationMistakes) return candidates;

    switch (question.operation) {
      case ArithmeticOperation.addition:
        candidates
          ..add(answer + step * Rational.fromInt(5))
          ..add(answer - step * Rational.fromInt(5));
      case ArithmeticOperation.subtraction:
        candidates
          ..add(-answer)
          ..add(-answer + step)
          ..add(-answer - step);
      case ArithmeticOperation.multiplication:
        candidates
          ..add(answer * Rational.fromInt(2))
          ..add(answer / Rational.fromInt(2));
      case ArithmeticOperation.division:
        candidates
          ..add(answer * Rational.fromInt(2))
          ..add(answer / Rational.fromInt(2));
        if (!answer.isZero) {
          candidates.add(Rational(BigInt.one) / answer);
        }
    }
    return candidates;
  }

  void _tryAdd(
    Rational candidate,
    ArithmeticQuestion question,
    List<ArithmeticAnswerOption> options,
    Set<Rational> exactValues,
    Set<Rational> displayValues,
  ) {
    final displayValue = _displayValue(candidate, question);
    if (!exactValues.add(candidate) || !displayValues.add(displayValue)) {
      return;
    }
    options.add(
      ArithmeticAnswerOption(
        value: candidate,
        text: _format(candidate, question),
        isCorrect: false,
      ),
    );
  }

  String _format(Rational value, ArithmeticQuestion question) =>
      value.formatForDisplay(decimalPlaces: question.decimalPrecision);

  Rational _displayValue(Rational value, ArithmeticQuestion question) {
    final precision = question.decimalPrecision;
    if (precision == null) return value;

    var display = _format(value, question);
    if (display.startsWith('≈ ')) display = display.substring(2);
    return Rational.fromDecimal(display);
  }

  static Random _makeRandom(Random? random, int? seed) {
    if (random != null && seed != null) {
      throw ArgumentError('Provide either random or seed, not both.');
    }
    return random ?? Random(seed);
  }
}
