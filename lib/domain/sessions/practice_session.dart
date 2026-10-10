import 'session_configuration.dart';
import 'session_models.dart';

enum SessionEndReason {
  questionCountReached,
  timeExpired,
  manuallyCompleted,
  userCancelled,
  interruptedWhileRunning,
  interruptedWhilePaused,
}

/// Database-independent session snapshot, including persisted attempts.
final class PersistedPracticeSession {
  PersistedPracticeSession({
    required this.id,
    required this.userId,
    required this.configuration,
    required this.state,
    required this.startedAt,
    required this.endedAt,
    required this.elapsedTime,
    required this.totalPausedTime,
    required this.pausedAt,
    required this.endReason,
    required List<QuestionAttempt> attempts,
  }) : attempts = List.unmodifiable(attempts);

  final String id;
  final String userId;
  final SessionConfiguration configuration;
  final SessionLifecycleState state;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Duration elapsedTime;
  final Duration totalPausedTime;
  final DateTime? pausedAt;
  final SessionEndReason? endReason;
  final List<QuestionAttempt> attempts;

  SessionResult? get result => state == SessionLifecycleState.completed
      ? SessionResult(
          userId: userId,
          attempts: attempts,
          elapsedTime: elapsedTime,
        )
      : null;
}

/// A repository request to persist the controller's latest lifecycle timing.
final class SessionLifecycleUpdate {
  const SessionLifecycleUpdate({
    required this.state,
    required this.changedAt,
    required this.elapsedTime,
    required this.totalPausedTime,
    this.pausedAt,
    this.endReason,
  });

  final SessionLifecycleState state;
  final DateTime changedAt;
  final Duration elapsedTime;
  final Duration totalPausedTime;
  final DateTime? pausedAt;
  final SessionEndReason? endReason;
}
