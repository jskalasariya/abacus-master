import 'arithmetic_operation.dart';
import 'arithmetic_question.dart';
import 'rational.dart';

/// Evaluates arithmetic expressions with exact rational arithmetic.
///
/// Supported syntax: decimal literals, unary `+`/`-`, `+`, `-`, `*`, `/`, and
/// parentheses. Multiplication and division take precedence over addition and
/// subtraction; operators at the same precedence are evaluated left to right.
/// Expressions are limited to 512 characters, 128 digits per literal, and 64
/// nested parenthesis pairs to keep input size bounded.
final class CalculationService {
  const CalculationService();

  static const maxExpressionLength = 512;

  /// Evaluates [expression] or throws [FormatException] for invalid syntax
  /// and [DivisionByZeroException] for a zero divisor.
  Rational evaluate(String expression) =>
      _ExpressionParser(expression).parse().value;

  /// Builds a question from a validated expression and its exact result.
  ///
  /// The question's operation is the outermost binary operation (the root of
  /// the expression after applying precedence). A single literal or a unary
  /// expression is valid for [evaluate], but cannot form a question because it
  /// has no arithmetic operation.
  ArithmeticQuestion questionFromExpression({
    required String expression,
    required ArithmeticDifficulty difficulty,
    int? decimalPrecision,
  }) {
    final result = _ExpressionParser(expression).parse();
    final operation = result.rootOperation;
    if (operation == null) {
      throw FormatException(
        'A question expression must contain a binary arithmetic operation.',
        expression,
      );
    }

    return ArithmeticQuestion(
      expression: expression,
      operation: operation,
      correctAnswer: result.value,
      difficulty: difficulty,
      decimalPrecision: decimalPrecision,
    );
  }
}

class _ExpressionParser {
  _ExpressionParser(this.source);

  final String source;
  int _index = 0;
  int _parenthesisDepth = 0;

  _Evaluation parse() {
    if (source.length > CalculationService.maxExpressionLength) {
      throw FormatException(
        'Expressions may contain at most '
        '${CalculationService.maxExpressionLength} characters.',
        source,
      );
    }
    if (source.trim().isEmpty) {
      throw FormatException('Expression must not be empty.', source, 0);
    }

    final result = _parseExpression();
    _skipWhitespace();
    if (_index != source.length) {
      _fail('Unexpected character `${source[_index]}`.');
    }
    return result;
  }

  _Evaluation _parseExpression() {
    var result = _parseTerm();
    while (true) {
      if (_consume('+')) {
        final right = _parseTerm();
        result = _Evaluation(
          result.value + right.value,
          ArithmeticOperation.addition,
        );
      } else if (_consume('-')) {
        final right = _parseTerm();
        result = _Evaluation(
          result.value - right.value,
          ArithmeticOperation.subtraction,
        );
      } else {
        return result;
      }
    }
  }

  _Evaluation _parseTerm() {
    var result = _parseUnary();
    while (true) {
      if (_consume('*')) {
        final right = _parseUnary();
        result = _Evaluation(
          result.value * right.value,
          ArithmeticOperation.multiplication,
        );
      } else if (_consume('/')) {
        final right = _parseUnary();
        result = _Evaluation(
          result.value / right.value,
          ArithmeticOperation.division,
        );
      } else {
        return result;
      }
    }
  }

  _Evaluation _parseUnary() {
    var negative = false;
    while (true) {
      _skipWhitespace();
      if (_consume('+')) continue;
      if (_consume('-')) {
        negative = !negative;
        continue;
      }
      break;
    }

    final value = _parsePrimary();
    return negative ? _Evaluation(-value.value, value.rootOperation) : value;
  }

  _Evaluation _parsePrimary() {
    _skipWhitespace();
    if (_index >= source.length) {
      _fail('Expected a number or parenthesized expression.');
    }

    if (_consume('(')) {
      _parenthesisDepth++;
      if (_parenthesisDepth > 64) {
        _fail('Expressions may contain at most 64 nested parentheses.');
      }
      final result = _parseExpression();
      if (!_consume(')')) {
        _fail('Expected a closing parenthesis.');
      }
      _parenthesisDepth--;
      return result;
    }

    return _parseNumber();
  }

  _Evaluation _parseNumber() {
    _skipWhitespace();
    final start = _index;
    var digitCount = 0;
    while (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
      digitCount++;
      _index++;
    }
    if (_index < source.length && source.codeUnitAt(_index) == 46) {
      _index++;
      while (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
        digitCount++;
        _index++;
      }
    }
    if (digitCount == 0) {
      _fail('Expected a decimal number.');
    }
    if (digitCount > Rational.maxInputDigits) {
      _fail(
        'Numbers may contain at most ${Rational.maxInputDigits} digits.',
        start,
      );
    }

    final literal = source.substring(start, _index);
    return _Evaluation(Rational.fromDecimal(literal), null);
  }

  bool _consume(String character) {
    _skipWhitespace();
    if (_index < source.length && source[_index] == character) {
      _index++;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (_index < source.length && source.codeUnitAt(_index) <= 32) {
      _index++;
    }
  }

  bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

  Never _fail(String message, [int? offset]) {
    throw FormatException(message, source, offset ?? _index);
  }
}

class _Evaluation {
  const _Evaluation(this.value, this.rootOperation);

  final Rational value;
  final ArithmeticOperation? rootOperation;
}
