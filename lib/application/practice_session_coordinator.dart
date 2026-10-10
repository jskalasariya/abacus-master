import 'dart:async';

import '../domain/arithmetic/rational.dart';
import '../domain/sessions/practice_session.dart';
import '../domain/sessions/practice_session_repository.dart';
import '../domain/sessions/session_configuration.dart';
import '../domain/sessions/session_models.dart';
import 'timed_practice_session_controller.dart';

/// Coordinates the in-memory session with durable storage.
///
/// Answers are prepared, persisted, and only then committed to the controller.
/// If SQLite fails, the same question remains available for retry. Lifecycle
/// terminal writes can be retried with [synchronize]; interrupted sessions
/// are later handled by the repository's startup recovery policy.
final class PracticeSessionCoordinator {
  PracticeSessionCoordinator({
    required this.configuration,
    required String? Function() authenticatedUserId,
    required this.repository,
    DateTime Function()? clock,
    int? seed,
  }) : _authenticatedUserId = authenticatedUserId,
       _clock = clock ?? DateTime.now,
       _controller = TimedPracticeSessionController(
         configuration: configuration,
         authenticatedUserId: authenticatedUserId,
         clock: clock,
         seed: seed,
       );

  final SessionConfiguration configuration;
  final String? Function() _authenticatedUserId;
  final PracticeSessionRepository repository;
  final DateTime Function() _clock;
  final TimedPracticeSessionController _controller;

  String? _userId;
  String? _sessionId;
  bool _busy = false;
  bool _ownerInvalidated = false;
  bool _terminalPersisted = false;
  SessionEndReason? _terminalReason;
  Future<void> _operationTail = Future<void>.value();

  String? get sessionId => _sessionId;
  String? get userId => _userId;
  SessionLifecycleState get state => _controller.state;
  SessionQuestion? get currentQuestion => _controller.currentQuestion;
  List<QuestionAttempt> get attempts => _controller.attempts;
  int get presentedQuestionCount => _controller.presentedQuestionCount;
  QuestionAttempt? attemptForQuestion(int number) =>
      _controller.attemptForQuestion(number);
  int get attemptedCount => _controller.attempts.length;
  Duration get elapsedTime => _controller.elapsedTime;
  Duration get remainingTime {
    final remaining = configuration.duration - elapsedTime;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> start() => _exclusive(() async {
    if (_controller.state != SessionLifecycleState.idle) {
      throw StateError('This practice session has already been started.');
    }
    final activeUserId = _authenticatedUserId();
    if (activeUserId == null || activeUserId.trim().isEmpty) {
      throw const UnauthenticatedSessionException();
    }
    final startedAt = _clock();
    _userId = activeUserId;
    final persisted = await repository.createSession(
      userId: activeUserId,
      configuration: configuration,
      startedAt: startedAt,
    );
    _sessionId = persisted.id;

    if (_authenticatedUserId() != activeUserId) {
      await _abandonBeforeStart(startedAt);
      throw const SessionOwnerChangedException();
    }
    _controller.start(at: startedAt);
  });

  Future<SessionQuestion?> nextQuestion() => _exclusive(() async {
    await _requireOwner();
    await _syncExpiration();
    return _controller.nextQuestion();
  });

  Future<SessionQuestion?> previousQuestion() => _exclusive(() async {
    await _requireOwner();
    await _syncExpiration();
    return _controller.previousQuestion();
  });

  Future<QuestionAttempt> submitAnswer(Rational answer) => _exclusive(() async {
    await _requireOwner();
    await _syncExpiration();
    final now = _clock();
    final prepared = _controller.prepareAnswer(answer, at: now);
    final current = _controller.currentQuestion!;
    final existing = _controller.attemptForQuestion(current.number);
    QuestionAttempt accepted;
    if (existing != null) {
      // Revisiting a question edits its selected answer in place. Its response
      // time remains the duration recorded for the first accepted answer.
      final updated = QuestionAttempt(
        questionNumber: prepared.questionNumber,
        expression: prepared.expression,
        correctAnswer: prepared.correctAnswer,
        selectedAnswer: prepared.selectedAnswer,
        isCorrect: prepared.isCorrect,
        responseTime: existing.responseTime,
        operation: prepared.operation,
        difficulty: prepared.difficulty,
      );
      await repository.updateAttempt(
        sessionId: _requiredSessionId,
        userId: _requiredUserId,
        attempt: updated,
      );
      accepted = _controller.commitPreparedAnswer(updated, at: now);
    } else {
      try {
        await repository.saveAttempt(
          sessionId: _requiredSessionId,
          userId: _requiredUserId,
          attempt: prepared,
          answeredAt: now,
        );
        accepted = _controller.commitPreparedAnswer(prepared, at: now);
      } on DuplicateQuestionAttemptException {
        // A process interruption can occur after SQLite commits an attempt but
        // before the in-memory controller records it. Accept only a durable
        // row that matches this exact selected answer, then commit it once.
        final saved = await repository.getSession(
          sessionId: _requiredSessionId,
          userId: _requiredUserId,
        );
        final durable = saved?.attempts
            .where((item) => item.questionNumber == prepared.questionNumber)
            .firstOrNull;
        if (durable == null) rethrow;
        if (_sameAnswerIntent(durable, prepared)) {
          accepted = _controller.commitPreparedAnswer(durable, at: now);
        } else {
          // If the learner chose a different option after an ambiguous write,
          // convert the durable row into the requested edit. Preserve the
          // original response duration and avoid a second sequence row.
          final revised = QuestionAttempt(
            questionNumber: prepared.questionNumber,
            expression: prepared.expression,
            correctAnswer: prepared.correctAnswer,
            selectedAnswer: prepared.selectedAnswer,
            isCorrect: prepared.isCorrect,
            responseTime: durable.responseTime,
            operation: prepared.operation,
            difficulty: prepared.difficulty,
          );
          await repository.updateAttempt(
            sessionId: _requiredSessionId,
            userId: _requiredUserId,
            attempt: revised,
          );
          accepted = _controller.commitPreparedAnswer(revised, at: now);
        }
      }
    }
    if (_controller.state == SessionLifecycleState.completed) {
      _terminalReason = SessionEndReason.questionCountReached;
      // The answer is already durable and committed in memory. A terminal
      // metadata write can be retried by synchronize/results without asking
      // the learner to resubmit an answer that was accepted exactly once.
      try {
        await _persistTerminal();
      } on PracticeSessionRepositoryException {
        // Keep the completed state; synchronize retries the lifecycle write.
      }
    }
    return accepted;
  });

  Future<void> pause() => _exclusive(() async {
    await _requireOwner();
    final now = _clock();
    _controller.checkExpiration(at: now);
    if (_controller.state == SessionLifecycleState.completed) {
      _terminalReason = SessionEndReason.timeExpired;
      await _persistTerminal();
      return;
    }
    final update = _controller.lifecycleSnapshot(
      state: SessionLifecycleState.paused,
      at: now,
    );
    await repository.updateLifecycle(
      sessionId: _requiredSessionId,
      userId: _requiredUserId,
      update: update,
    );
    _controller.pause(at: now);
  });

  Future<void> resume() => _exclusive(() async {
    await _requireOwner();
    final now = _clock();
    final update = _controller.lifecycleSnapshot(
      state: SessionLifecycleState.running,
      at: now,
    );
    await repository.updateLifecycle(
      sessionId: _requiredSessionId,
      userId: _requiredUserId,
      update: update,
    );
    _controller.resume(at: now);
  });

  Future<void> complete() => _exclusive(() async {
    await _requireOwner();
    final now = _clock();
    _controller.checkExpiration(at: now);
    if (_controller.state == SessionLifecycleState.completed) {
      _terminalReason = SessionEndReason.timeExpired;
      await _persistTerminal();
      return;
    }
    final update = _controller.lifecycleSnapshot(
      state: SessionLifecycleState.completed,
      at: now,
      endReason: SessionEndReason.manuallyCompleted,
    );
    await repository.updateLifecycle(
      sessionId: _requiredSessionId,
      userId: _requiredUserId,
      update: update,
    );
    _controller.complete(at: now);
    _terminalReason = SessionEndReason.manuallyCompleted;
    _terminalPersisted = true;
  });

  Future<void> cancel() => _exclusive(() async {
    await _requireOwner();
    final now = _clock();
    _controller.checkExpiration(at: now);
    if (_controller.state == SessionLifecycleState.completed) {
      _terminalReason = SessionEndReason.timeExpired;
      await _persistTerminal();
      return;
    }
    final update = _controller.lifecycleSnapshot(
      state: SessionLifecycleState.cancelled,
      at: now,
      endReason: SessionEndReason.userCancelled,
    );
    await repository.updateLifecycle(
      sessionId: _requiredSessionId,
      userId: _requiredUserId,
      update: update,
    );
    _controller.cancel(at: now);
    _terminalReason = SessionEndReason.userCancelled;
    _terminalPersisted = true;
  });

  /// Called by a visible countdown timer and when the app resumes. Since the
  /// controller uses timestamps, background time counts unless explicitly
  /// paused; elapsed time is never inferred from missed timer ticks.
  Future<void> synchronize() async {
    if (_busy) return;
    await _exclusive(() async {
      await _requireOwner();
      await _syncExpiration();
    });
  }

  Future<SessionResult?> getPersistedResult() => _exclusive(() async {
    await _requireOwner();
    await _syncExpiration();
    if (_controller.state != SessionLifecycleState.completed ||
        !_terminalPersisted) {
      return null;
    }
    return repository.getResult(
      sessionId: _requiredSessionId,
      userId: _requiredUserId,
    );
  });

  Future<PersistedPracticeSession?> getPersistedSession() =>
      _exclusive(() async {
        await _requireOwner();
        return repository.getSession(
          sessionId: _requiredSessionId,
          userId: _requiredUserId,
        );
      });

  Future<void> _syncExpiration() async {
    _controller.checkExpiration(at: _clock());
    if (_controller.state == SessionLifecycleState.completed &&
        !_terminalPersisted) {
      _terminalReason ??=
          _controller.attempts.length >= configuration.questionCount
          ? SessionEndReason.questionCountReached
          : SessionEndReason.timeExpired;
      await _persistTerminal();
    }
  }

  Future<void> _persistTerminal() async {
    if (_terminalPersisted) return;
    final state = _controller.state;
    if (state != SessionLifecycleState.completed &&
        state != SessionLifecycleState.cancelled) {
      throw StateError(
        'Cannot persist a terminal state for an active session.',
      );
    }
    final reason = _terminalReason ?? SessionEndReason.timeExpired;
    final update = _controller.lifecycleSnapshot(
      state: state,
      at: _clock(),
      endReason: reason,
    );
    await repository.updateLifecycle(
      sessionId: _requiredSessionId,
      userId: _requiredUserId,
      update: update,
    );
    _terminalPersisted = true;
  }

  Future<void> _requireOwner() async {
    if (_ownerInvalidated) throw const SessionOwnerChangedException();
    final owner = _userId;
    if (owner == null || _sessionId == null) {
      throw StateError('Start the practice session first.');
    }
    if (_authenticatedUserId() == owner) return;

    _ownerInvalidated = true;
    final state = _controller.state;
    if (state == SessionLifecycleState.running ||
        state == SessionLifecycleState.paused) {
      final now = _clock();
      final update = _controller.lifecycleSnapshot(
        state: SessionLifecycleState.cancelled,
        at: now,
        endReason: SessionEndReason.userCancelled,
      );
      try {
        await repository.updateLifecycle(
          sessionId: _requiredSessionId,
          userId: owner,
          update: update,
        );
        _controller.cancel(at: now);
        _terminalPersisted = true;
      } catch (_) {
        // Keep the controller inaccessible. Startup recovery will safely
        // cancel the durable session if this cancellation write also failed.
      }
    }
    throw const SessionOwnerChangedException();
  }

  Future<void> _abandonBeforeStart(DateTime at) async {
    try {
      await repository.updateLifecycle(
        sessionId: _requiredSessionId,
        userId: _requiredUserId,
        update: SessionLifecycleUpdate(
          state: SessionLifecycleState.cancelled,
          changedAt: at,
          elapsedTime: Duration.zero,
          totalPausedTime: Duration.zero,
          endReason: SessionEndReason.userCancelled,
        ),
      );
      _terminalPersisted = true;
    } catch (_) {
      // Startup recovery handles the still-running row.
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      _busy = true;
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _busy = false;
      }
    });
    return result.future;
  }

  String get _requiredUserId => _userId!;
  String get _requiredSessionId => _sessionId!;

  bool _sameAnswerIntent(QuestionAttempt persisted, QuestionAttempt retry) =>
      persisted.questionNumber == retry.questionNumber &&
      persisted.expression == retry.expression &&
      persisted.correctAnswer == retry.correctAnswer &&
      persisted.selectedAnswer == retry.selectedAnswer &&
      persisted.isCorrect == retry.isCorrect &&
      persisted.operation == retry.operation &&
      persisted.difficulty == retry.difficulty;
}

final class UnauthenticatedSessionException implements Exception {
  const UnauthenticatedSessionException();
}

final class SessionOwnerChangedException implements Exception {
  const SessionOwnerChangedException();
}
