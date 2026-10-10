import 'package:flutter_test/flutter_test.dart';

import 'package:abacus_master/domain/arithmetic/arithmetic_operation.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_question.dart';
import 'package:abacus_master/domain/arithmetic/calculation_service.dart';
import 'package:abacus_master/domain/arithmetic/rational.dart';

void main() {
  const service = CalculationService();

  group('CalculationService arithmetic operations', () {
    test('evaluates addition exactly', () {
      expect(service.evaluate('12 + 7'), Rational.fromInt(19));
    });

    test('evaluates subtraction exactly', () {
      expect(service.evaluate('12 - 19'), Rational.fromInt(-7));
    });

    test('evaluates multiplication exactly', () {
      expect(service.evaluate('12 * 7'), Rational.fromInt(84));
    });

    test('evaluates division as an exact rational when needed', () {
      expect(service.evaluate('7 / 2'), Rational(BigInt.from(7), BigInt.two));
    });

    test('handles negative operands and results', () {
      expect(service.evaluate('-2.5 * 4'), Rational.fromInt(-10));
      expect(service.evaluate('(-3) + 1.25'), Rational.fromDecimal('-1.75'));
      expect(
        service.evaluate('10 / -4'),
        Rational(BigInt.from(-5), BigInt.two),
      );
    });

    test('uses precedence and left associativity', () {
      expect(service.evaluate('2 + 3 * 4'), Rational.fromInt(14));
      expect(service.evaluate('(2 + 3) * 4'), Rational.fromInt(20));
      expect(service.evaluate('10 - 3 - 2'), Rational.fromInt(5));
      expect(service.evaluate('8 / 4 * 2'), Rational.fromInt(4));
    });

    test('evaluates decimal expressions without binary float errors', () {
      final sum = service.evaluate('0.1 + 0.2');
      expect(sum, Rational.fromDecimal('0.3'));
      expect(service.evaluate('0.10 + 0.20'), sum);
      expect(service.evaluate('1.20 + .3'), Rational.fromDecimal('1.5'));
    });

    test('rejects division by zero directly and through an expression', () {
      expect(
        () => service.evaluate('1 / 0'),
        throwsA(isA<DivisionByZeroException>()),
      );
      expect(
        () => service.evaluate('10 / (2 - 2)'),
        throwsA(isA<DivisionByZeroException>()),
      );
    });

    test('rejects malformed expressions rather than guessing', () {
      for (final expression in ['1 +', '2(3)', '1.2.3', '(1 + 2', '']) {
        expect(
          () => service.evaluate(expression),
          throwsA(isA<FormatException>()),
          reason: 'Expression `$expression` should be rejected.',
        );
      }
    });
  });

  group('Rational', () {
    test('normalizes signs and equivalent fractions', () {
      expect(
        Rational(BigInt.from(2), BigInt.from(4)),
        Rational(BigInt.one, BigInt.two),
      );
      expect(
        Rational(BigInt.from(1), BigInt.from(-2)),
        Rational(BigInt.from(-1), BigInt.two),
      );
    });

    test('formats terminating and repeating answers exactly', () {
      expect(Rational(BigInt.from(1), BigInt.from(8)).toExactString(), '0.125');
      expect(Rational(BigInt.from(1), BigInt.from(3)).toExactString(), '1/3');
      expect(
        Rational(BigInt.from(-15), BigInt.from(10)).toExactString(),
        '-1.5',
      );
    });

    test('rounds only at explicit precision and marks changed values', () {
      expect(
        Rational(BigInt.one, BigInt.from(8)).formatForDisplay(decimalPlaces: 2),
        '≈ 0.13',
      );
      expect(
        Rational(
          BigInt.from(-1),
          BigInt.from(8),
        ).formatForDisplay(decimalPlaces: 2),
        '≈ -0.13',
      );
      expect(
        Rational(
          BigInt.from(5),
          BigInt.from(4),
        ).formatForDisplay(decimalPlaces: 2),
        '1.25',
      );
      expect(
        Rational(
          BigInt.from(5),
          BigInt.from(4),
        ).formatForDisplay(decimalPlaces: 1),
        '≈ 1.3',
      );
      expect(
        Rational(
          BigInt.from(-1),
          BigInt.from(20),
        ).formatForDisplay(decimalPlaces: 1),
        '≈ -0.1',
      );
      expect(Rational.fromInt(0).formatForDisplay(decimalPlaces: 2), '0.00');
    });

    test('checks precision bounds and rejects zero denominators', () {
      expect(() => Rational(BigInt.one, BigInt.zero), throwsArgumentError);
      expect(
        () => Rational(BigInt.one).formatForDisplay(decimalPlaces: -1),
        throwsRangeError,
      );
      expect(
        () => Rational(BigInt.one).formatForDisplay(decimalPlaces: 101),
        throwsRangeError,
      );
    });
  });

  group('ArithmeticQuestion', () {
    test('stores exact result and optional display precision', () {
      final question = service.questionFromExpression(
        expression: '1 / 8',
        difficulty: ArithmeticDifficulty.medium,
        decimalPrecision: 2,
      );

      expect(question, isA<ArithmeticQuestion>());
      expect(question.expression, '1 / 8');
      expect(question.operation, ArithmeticOperation.division);
      expect(question.correctAnswer, Rational(BigInt.one, BigInt.from(8)));
      expect(question.difficulty, ArithmeticDifficulty.medium);
      expect(question.formattedAnswer, '≈ 0.13');
    });

    test('identifies the outer operation after precedence is applied', () {
      final question = service.questionFromExpression(
        expression: '2 + 3 * 4',
        difficulty: ArithmeticDifficulty.beginner,
      );

      expect(question.correctAnswer, Rational.fromInt(14));
      expect(question.operation, ArithmeticOperation.addition);
      expect(question.formattedAnswer, '14');
    });

    test('requires a binary operation to create a question', () {
      expect(
        () => service.questionFromExpression(
          expression: '4.5',
          difficulty: ArithmeticDifficulty.advanced,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ArithmeticQuestion(
          expression: '2 + 2',
          operation: ArithmeticOperation.addition,
          correctAnswer: Rational.fromInt(4),
          difficulty: ArithmeticDifficulty.beginner,
          decimalPrecision: 101,
        ),
        throwsRangeError,
      );
    });
  });
}
