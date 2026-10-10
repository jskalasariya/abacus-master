import '../arithmetic/arithmetic_operation.dart';
import '../answer_feedback_mode.dart';

/// Public profile data. Credential material stays inside the persistence layer.
final class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String username;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.id == id &&
      other.username == username &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, username, createdAt, updatedAt);
}

final class UserSettings {
  const UserSettings({
    required this.userId,
    this.difficulty = ArithmeticDifficulty.beginner,
    this.decimalPrecision = 0,
    this.answerFeedbackMode = AnswerFeedbackMode.immediate,
  }) : assert(decimalPrecision >= 0 && decimalPrecision <= 3);

  final String userId;
  final ArithmeticDifficulty difficulty;
  final int decimalPrecision;
  final AnswerFeedbackMode answerFeedbackMode;

  UserSettings copyWith({
    ArithmeticDifficulty? difficulty,
    int? decimalPrecision,
    AnswerFeedbackMode? answerFeedbackMode,
  }) => UserSettings(
    userId: userId,
    difficulty: difficulty ?? this.difficulty,
    decimalPrecision: decimalPrecision ?? this.decimalPrecision,
    answerFeedbackMode: answerFeedbackMode ?? this.answerFeedbackMode,
  );

  @override
  bool operator ==(Object other) =>
      other is UserSettings &&
      other.userId == userId &&
      other.difficulty == difficulty &&
      other.decimalPrecision == decimalPrecision &&
      other.answerFeedbackMode == answerFeedbackMode;

  @override
  int get hashCode =>
      Object.hash(userId, difficulty, decimalPrecision, answerFeedbackMode);
}
