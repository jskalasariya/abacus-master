/// An exact rational number stored as a reduced numerator/denominator pair.
///
/// Decimal input is parsed from its text (for example, `0.1` becomes 1/10),
/// so arithmetic never depends on binary floating-point approximation. The
/// representation is exact for terminating and repeating decimals alike.
/// It is limited by available memory and CPU because [BigInt] values can grow
/// as expressions are evaluated.
final class Rational {
  factory Rational(BigInt numerator, [BigInt? denominator]) {
    var normalizedNumerator = numerator;
    var normalizedDenominator = denominator ?? BigInt.one;
    if (normalizedDenominator == BigInt.zero) {
      throw ArgumentError.value(
        denominator,
        'denominator',
        'Must not be zero.',
      );
    }

    if (normalizedDenominator.isNegative) {
      normalizedNumerator = -normalizedNumerator;
      normalizedDenominator = -normalizedDenominator;
    }

    final divisor = normalizedNumerator.abs().gcd(normalizedDenominator);
    return Rational._(
      normalizedNumerator ~/ divisor,
      normalizedDenominator ~/ divisor,
    );
  }

  factory Rational.fromInt(int value) => Rational(BigInt.from(value));

  /// Parses a base-10 integer or decimal without passing through `double`.
  ///
  /// An optional sign and forms such as `.25` and `2.` are accepted.
  factory Rational.fromDecimal(String text) {
    final match = RegExp(r'^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))$')
        .firstMatch(text);
    if (match == null) {
      throw FormatException('Invalid decimal number.', text);
    }

    final sign = match.group(1) == '-' ? -1 : 1;
    final wholeText = match.group(2) ?? '0';
    final fractionalText = match.group(3) ?? match.group(4) ?? '';
    final digits = '$wholeText$fractionalText';
    if (digits.length > maxInputDigits) {
      throw FormatException(
        'Decimal numbers may contain at most $maxInputDigits digits.',
        text,
      );
    }

    final scale = BigInt.from(10).pow(fractionalText.length);
    final magnitude = BigInt.parse(digits.isEmpty ? '0' : digits);
    final numerator = sign < 0 ? -magnitude : magnitude;
    return Rational(numerator, scale);
  }

  const Rational._(this.numerator, this.denominator);

  /// Maximum number of decimal digits accepted in one input literal.
  static const maxInputDigits = 128;

  /// Maximum number of places used by explicit decimal formatting.
  static const maxDisplayPrecision = 100;

  final BigInt numerator;
  final BigInt denominator;

  bool get isInteger => denominator == BigInt.one;
  bool get isZero => numerator == BigInt.zero;

  Rational operator +(Rational other) => Rational(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  Rational operator -(Rational other) => Rational(
    numerator * other.denominator - other.numerator * denominator,
    denominator * other.denominator,
  );

  Rational operator -() => Rational(-numerator, denominator);

  Rational operator *(Rational other) =>
      Rational(numerator * other.numerator, denominator * other.denominator);

  Rational operator /(Rational other) {
    if (other.isZero) {
      throw const DivisionByZeroException();
    }
    return Rational(
      numerator * other.denominator,
      denominator * other.numerator,
    );
  }

  /// Formats the exact value, using a finite decimal where possible and a
  /// reduced fraction for repeating decimals.
  String toExactString() {
    if (isZero) return '0';

    var remaining = denominator;
    var twos = 0;
    var fives = 0;
    while (remaining % BigInt.two == BigInt.zero) {
      remaining ~/= BigInt.two;
      twos++;
    }
    while (remaining % BigInt.from(5) == BigInt.zero) {
      remaining ~/= BigInt.from(5);
      fives++;
    }
    if (remaining != BigInt.one) {
      return '$numerator/$denominator';
    }

    final scale = twos > fives ? twos : fives;
    final scaledNumerator =
        numerator *
        BigInt.two.pow(scale - twos) *
        BigInt.from(5).pow(scale - fives);
    return _formatScaledInteger(
      scaledNumerator,
      scale,
      trimTrailingZeros: true,
    );
  }

  /// Formats at an explicitly requested number of decimal places.
  ///
  /// Rounding uses half away from zero. If the displayed decimal differs from
  /// this exact value, the result starts with `≈` to make the approximation
  /// explicit. Omitting [decimalPlaces] always preserves the exact value.
  String formatForDisplay({int? decimalPlaces}) {
    if (decimalPlaces == null) return toExactString();
    if (decimalPlaces < 0 || decimalPlaces > maxDisplayPrecision) {
      throw RangeError.range(
        decimalPlaces,
        0,
        maxDisplayPrecision,
        'decimalPlaces',
      );
    }

    final factor = BigInt.from(10).pow(decimalPlaces);
    final scaledMagnitude = numerator.abs() * factor;
    var roundedMagnitude = scaledMagnitude ~/ denominator;
    final remainder = scaledMagnitude % denominator;
    if (remainder * BigInt.two >= denominator) {
      roundedMagnitude += BigInt.one;
    }

    final signedRounded =
        numerator.isNegative && roundedMagnitude != BigInt.zero
        ? -roundedMagnitude
        : roundedMagnitude;
    final formatted = _formatScaledInteger(
      signedRounded,
      decimalPlaces,
      trimTrailingZeros: false,
    );
    return remainder == BigInt.zero ? formatted : '≈ $formatted';
  }

  static String _formatScaledInteger(
    BigInt value,
    int scale, {
    required bool trimTrailingZeros,
  }) {
    final isNegative = value.isNegative;
    var digits = value.abs().toString();
    if (scale == 0) return '${isNegative ? '-' : ''}$digits';

    digits = digits.padLeft(scale + 1, '0');
    final decimalIndex = digits.length - scale;
    var fractional = digits.substring(decimalIndex);
    if (trimTrailingZeros) {
      fractional = fractional.replaceFirst(RegExp(r'0+$'), '');
    }
    final whole = digits.substring(0, decimalIndex);
    final sign = isNegative ? '-' : '';
    return fractional.isEmpty ? '$sign$whole' : '$sign$whole.$fractional';
  }

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => toExactString();
}

/// Thrown when a calculation attempts to divide by zero.
final class DivisionByZeroException implements Exception {
  const DivisionByZeroException();

  @override
  String toString() =>
      'DivisionByZeroException: division by zero is undefined.';
}
