import 'practice_session.dart';
import 'session_models.dart';
import 'session_configuration.dart';
import 'practice_history_models.dart';

abstract interface class PracticeSessionRepository {
  Future<PersistedPracticeSession> createSession({
    required String userId,
    required SessionConfiguration configuration,
    required DateTime startedAt,
  });

  /// Saves each sequence exactly once and advances the durable attempt count
  /// in the same transaction as the attempt insert.
  Future<void> saveAttempt({
    required String sessionId,
    required String userId,
    required QuestionAttempt attempt,
    required DateTime answeredAt,
  });

  /// Replaces the selected answer for an existing sequence. The original
  /// response time and answer timestamp remain the time of the first answer.
  Future<void> updateAttempt({
    required String sessionId,
    required String userId,
    required QuestionAttempt attempt,
  });

  Future<PersistedPracticeSession> updateLifecycle({
    required String sessionId,
    required String userId,
    required SessionLifecycleUpdate update,
  });

  Future<PersistedPracticeSession?> getSession({
    required String sessionId,
    required String userId,
  });

  Future<List<PersistedPracticeSession>> listCompletedSessions(String userId);

  /// Returns compact, newest-first history without loading question details.
  Future<List<PracticeSessionSummary>> listCompletedSessionSummaries(
    String userId, {
    int limit = 20,
    int offset = 0,
  });

  /// Aggregates completed-session metrics in storage and loads only a bounded
  /// set of compact summaries for the recent-progress section.
  Future<PracticeStatistics> getStatistics(
    String userId, {
    int recentLimit = 10,
  });

  Future<SessionResult?> getResult({
    required String sessionId,
    required String userId,
  });

  /// Safely cancels active or paused sessions left behind by a process exit.
  /// An unanswered question is discarded, never synthesized as an attempt.
  Future<List<PersistedPracticeSession>> recoverUnfinishedSessions({
    DateTime? recoveredAt,
  });
}

sealed class PracticeSessionRepositoryException implements Exception {
  const PracticeSessionRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

final class SessionNotFoundException
    extends PracticeSessionRepositoryException {
  const SessionNotFoundException(super.message);
}

final class SessionOwnershipException
    extends PracticeSessionRepositoryException {
  const SessionOwnershipException(super.message);
}

final class DuplicateQuestionAttemptException
    extends PracticeSessionRepositoryException {
  const DuplicateQuestionAttemptException(super.message);
}

final class InvalidSessionDataException
    extends PracticeSessionRepositoryException {
  const InvalidSessionDataException(super.message);
}

final class SessionStorageException extends PracticeSessionRepositoryException {
  const SessionStorageException(super.message);
}
