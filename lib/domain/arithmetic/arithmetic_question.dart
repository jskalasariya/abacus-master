import 'arithmetic_operation.dart';
import 'rational.dart';

/// A fixed arithmetic question and its exact answer.
///
/// [decimalPrecision], when supplied, is a display preference in fractional
/// decimal places. If displaying at that precision requires rounding,
/// [formattedAnswer] marks the result with `≈`; [correctAnswer] remains exact.
final class ArithmeticQuestion {
  ArithmeticQuestion({
    required this.expression,
    required this.operation,
    required this.correctAnswer,
    required this.difficulty,
    this.decimalPrecision,
  }) {
    if (expression.trim().isEmpty) {
      throw ArgumentError.value(expression, 'expression', 'Must not be empty.');
    }
    if (decimalPrecision != null &&
        (decimalPrecision! < 0 ||
            decimalPrecision! > Rational.maxDisplayPrecision)) {
      throw RangeError.range(
        decimalPrecision!,
        0,
        Rational.maxDisplayPrecision,
        'decimalPrecision',
      );
    }
  }

  final String expression;
  final ArithmeticOperation operation;
  final Rational correctAnswer;
  final ArithmeticDifficulty difficulty;

  /// Optional number of fractional places to show when presenting the answer.
  final int? decimalPrecision;

  /// An exact answer, or an explicitly marked approximation at the requested
  /// [decimalPrecision].
  String get formattedAnswer =>
      correctAnswer.formatForDisplay(decimalPlaces: decimalPrecision);
}
