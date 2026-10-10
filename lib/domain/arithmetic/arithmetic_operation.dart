/// The four arithmetic operations supported by the question engine.
enum ArithmeticOperation {
  addition('+'),
  subtraction('-'),
  multiplication('*'),
  division('/');

  const ArithmeticOperation(this.symbol);

  /// The ASCII operator used in arithmetic expressions.
  final String symbol;
}

/// Broad question difficulty labels, independent of how questions are made.
enum ArithmeticDifficulty { beginner, medium, advanced }
