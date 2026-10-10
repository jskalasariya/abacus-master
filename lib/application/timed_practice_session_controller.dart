import 'dart:math';

import '../domain/arithmetic/arithmetic_difficulty_config.dart';
import '../domain/arithmetic/arithmetic_operation.dart';
import '../domain/arithmetic/arithmetic_question.dart';
import '../domain/arithmetic/arithmetic_question_generator.dart';
import '../domain/arithmetic/multiple_choice_option_generator.dart';
import '../domain/arithmetic/rational.dart';
import '../domain/sessions/session_configuration.dart';
import '../domain/sessions/practice_session.dart';
import '../domain/sessions/session_models.dart';

/// Drives one in-memory practice session. The UI/application layer supplies
/// the authenticated user's ID source, which is checked when a session starts.
///
/// Expiration is evaluated on every state-changing operation and by
/// [checkExpiration], which a future screen can call while it is displayed.
/// Time is always derived from [clock], with paused intervals subtracted.
final class TimedPracticeSessionController {
  TimedPracticeSessionController({
    required this.configuration,
    required this.authenticatedUserId,
    DateTime Function()? clock,
    int? seed,
    ArithmeticQuestionGenerator? questionGenerator,
    MultipleChoiceOptionGenerator? optionGenerator,
  }) : _clock = clock ?? DateTime.now,
       _random = Random(seed),
       _questionGenerator =
           questionGenerator ??
           ArithmeticQuestionGenerator(
             seed: seed == null ? null : seed + 1,
             configurations: _questionConfigurations(configuration),
           ),
       _optionGenerator =
           optionGenerator ??
           MultipleChoiceOptionGenerator(seed: seed == null ? null : seed + 2);

  final SessionConfiguration configuration;
  final String? Function() authenticatedUserId;
  final DateTime Function() _clock;
  final Random _random;
  final ArithmeticQuestionGenerator _questionGenerator;
  final MultipleChoiceOptionGenerator _optionGenerator;
  final List<QuestionAttempt> _attempts = [];
  final List<SessionQuestion> _questionHistory = [];
  final Map<int, Duration> _questionTimeBeforePause = {};

  SessionLifecycleState _state = SessionLifecycleState.idle;
  String? _userId;
  DateTime? _startedAt;
  DateTime? _finishedAt;
  DateTime? _pausedAt;
  Duration _totalPaused = Duration.zero;
  int _historyIndex = -1;
  DateTime? _questionActiveSince;
  Duration _questionElapsedBeforePause = Duration.zero;

  DateTime? get startedAt => _startedAt;
  Duration get totalPausedTime => _totalPaused;

  SessionLifecycleState get state {
    checkExpiration();
    return _state;
  }

  String? get userId => _userId;

  SessionQuestion? get currentQuestion {
    checkExpiration();
    if (_state == SessionLifecycleState.completed ||
        _state == SessionLifecycleState.cancelled ||
        _historyIndex < 0) {
      return null;
    }
    return _questionHistory[_historyIndex];
  }

  List<QuestionAttempt> get attempts => List.unmodifiable(_attempts);
  int get presentedQuestionCount => _questionHistory.length;

  QuestionAttempt? attemptForQuestion(int number) {
    for (final attempt in _attempts) {
      if (attempt.questionNumber == number) return attempt;
    }
    return null;
  }

  SessionResult? get result {
    checkExpiration();
    return _state == SessionLifecycleState.completed ? _buildResult() : null;
  }

  Duration get elapsedTime {
    checkExpiration();
    return _elapsedAt(_clock());
  }

  void start({DateTime? at}) {
    if (_state != SessionLifecycleState.idle) {
      throw StateError('A session can only be started once.');
    }
    final activeUserId = authenticatedUserId();
    if (activeUserId == null || activeUserId.trim().isEmpty) {
      throw StateError('An authenticated user is required to start a session.');
    }
    _userId = activeUserId;
    _startedAt = at ?? _clock();
    _state = SessionLifecycleState.running;
  }

  /// Returns the next shuffled question, or null when the session has ended.
  SessionQuestion? nextQuestion() {
    checkExpiration();
    if (_state == SessionLifecycleState.completed ||
        _state == SessionLifecycleState.cancelled) {
      return null;
    }
    _requireState(SessionLifecycleState.running);
    if (_historyIndex >= 0) {
      final shown = _questionHistory[_historyIndex];
      if (attemptForQuestion(shown.number) == null &&
          _historyIndex + 1 >= _questionHistory.length) {
        throw StateError('Submit or cancel the current question first.');
      }
      if (_historyIndex + 1 < _questionHistory.length) {
        _historyIndex++;
        final next = _questionHistory[_historyIndex];
        if (attemptForQuestion(next.number) == null) {
          _questionElapsedBeforePause =
              _questionTimeBeforePause[next.number] ?? Duration.zero;
          _questionActiveSince = _clock();
        }
        return _questionHistory[_historyIndex];
      }
    }
    if (_attempts.length >= configuration.questionCount) {
      _finish(_clock());
      return null;
    }

    final question = _generateQuestion();
    final sessionQuestion = SessionQuestion(
      number: _questionHistory.length + 1,
      question: question,
      options: _optionGenerator.generate(question),
    );
    _questionHistory.add(sessionQuestion);
    _historyIndex = _questionHistory.length - 1;
    _questionActiveSince = _clock();
    _questionElapsedBeforePause = Duration.zero;
    return sessionQuestion;
  }

  /// Submits one exact answer. A question can be submitted only once.
  QuestionAttempt prepareAnswer(Rational answer, {required DateTime at}) {
    checkExpiration(at: at);
    _requireState(SessionLifecycleState.running);
    final activeQuestion = currentQuestion;
    if (activeQuestion == null) {
      throw StateError('There is no unanswered question.');
    }
    if (!activeQuestion.options.any((option) => option.value == answer)) {
      throw ArgumentError.value(
        answer,
        'answer',
        'The submitted answer was not one of the presented choices.',
      );
    }

    final previousAttempt = attemptForQuestion(activeQuestion.number);
    final activeSince = _questionActiveSince;
    final responseTime =
        previousAttempt?.responseTime ??
        _questionElapsedBeforePause +
            (activeSince == null
                ? Duration.zero
                : _nonNegative(at.difference(activeSince)));
    return QuestionAttempt(
      questionNumber: activeQuestion.number,
      expression: activeQuestion.expression,
      correctAnswer: activeQuestion.correctAnswer,
      selectedAnswer: answer,
      isCorrect: answer == activeQuestion.correctAnswer,
      responseTime: responseTime,
      operation: activeQuestion.operation,
      difficulty: activeQuestion.question.difficulty,
    );
  }

  /// Commits a prepared attempt after durable persistence succeeds.
  QuestionAttempt commitPreparedAnswer(
    QuestionAttempt attempt, {
    required DateTime at,
  }) {
    final verified = prepareAnswer(attempt.selectedAnswer, at: at);
    if (!_sameAttempt(verified, attempt)) {
      throw StateError('The prepared answer no longer matches the question.');
    }
    final oldIndex = _attempts.indexWhere(
      (saved) => saved.questionNumber == attempt.questionNumber,
    );
    if (oldIndex >= 0) {
      _attempts[oldIndex] = attempt;
    } else {
      _attempts.add(attempt);
    }
    _questionActiveSince = null;
    _questionElapsedBeforePause = Duration.zero;

    if (_attempts.length >= configuration.questionCount) {
      _finish(at);
    }
    return attempt;
  }

  /// Moves to a previously presented answered question without changing the
  /// session timer. The first response duration remains attached to the item.
  SessionQuestion? previousQuestion() {
    checkExpiration();
    _requireState(SessionLifecycleState.running);
    if (_historyIndex <= 0) return null;
    final activeSince = _questionActiveSince;
    if (activeSince != null) {
      _questionElapsedBeforePause += _nonNegative(
        _clock().difference(activeSince),
      );
    }
    if (_historyIndex >= 0) {
      _questionTimeBeforePause[_questionHistory[_historyIndex].number] =
          _questionElapsedBeforePause;
    }
    _historyIndex--;
    _questionActiveSince = null;
    _questionElapsedBeforePause = Duration.zero;
    if (attemptForQuestion(_questionHistory[_historyIndex].number) == null) {
      throw StateError('Only answered questions can be revisited.');
    }
    return _questionHistory[_historyIndex];
  }

  QuestionAttempt submitAnswer(Rational answer) {
    final at = _clock();
    final prepared = prepareAnswer(answer, at: at);
    return commitPreparedAnswer(prepared, at: at);
  }

  void pause({DateTime? at}) {
    checkExpiration(at: at);
    _requireState(SessionLifecycleState.running);
    final now = at ?? _clock();
    _pausedAt = now;
    final questionActiveSince = _questionActiveSince;
    if (currentQuestion != null && questionActiveSince != null) {
      _questionElapsedBeforePause += _nonNegative(
        now.difference(questionActiveSince),
      );
      _questionActiveSince = null;
    }
    _state = SessionLifecycleState.paused;
  }

  void resume({DateTime? at}) {
    _requireState(SessionLifecycleState.paused);
    final now = at ?? _clock();
    final pausedAt = _pausedAt!;
    _totalPaused += _nonNegative(now.difference(pausedAt));
    _pausedAt = null;
    if (currentQuestion != null &&
        attemptForQuestion(currentQuestion!.number) == null) {
      _questionActiveSince = now;
    }
    _state = SessionLifecycleState.running;
    checkExpiration(at: now);
  }

  /// Completes early and returns immutable aggregates for submitted attempts.
  SessionResult complete({DateTime? at}) {
    final now = at ?? _clock();
    checkExpiration(at: now);
    if (_state == SessionLifecycleState.completed) return result!;
    if (_state != SessionLifecycleState.running &&
        _state != SessionLifecycleState.paused) {
      throw StateError('Only an active session can be completed.');
    }
    _finish(now);
    return result!;
  }

  void cancel({DateTime? at}) {
    checkExpiration(at: at);
    if (_state != SessionLifecycleState.running &&
        _state != SessionLifecycleState.paused) {
      throw StateError('Only an active session can be cancelled.');
    }
    _finishedAt = at ?? _clock();
    _closePausedInterval(_finishedAt!);
    _questionActiveSince = null;
    _state = SessionLifecycleState.cancelled;
  }

  /// Synchronizes the lifecycle with the injected clock. A future UI can poll
  /// this while visible; commands also call it, so expired sessions cannot
  /// accept or issue questions even if a tick was delayed.
  void checkExpiration({DateTime? at}) {
    if (_state != SessionLifecycleState.running) return;
    final now = at ?? _clock();
    if (_elapsedAt(now) >= configuration.duration) _finish(now);
  }

  /// Captures timing for a repository update without changing controller state.
  SessionLifecycleUpdate lifecycleSnapshot({
    required SessionLifecycleState state,
    required DateTime at,
    SessionEndReason? endReason,
  }) {
    final isPaused = state == SessionLifecycleState.paused;
    var pausedTotal = _totalPaused;
    if (_state == SessionLifecycleState.paused &&
        !isPaused &&
        _pausedAt != null) {
      pausedTotal += _nonNegative(at.difference(_pausedAt!));
    }
    return SessionLifecycleUpdate(
      state: state,
      changedAt: at,
      elapsedTime: _elapsedAt(at),
      totalPausedTime: pausedTotal,
      pausedAt: isPaused ? (_pausedAt ?? at) : null,
      endReason: endReason,
    );
  }

  ArithmeticQuestion _generateQuestion() {
    final mayGenerateMixed =
        configuration.allowMixedOperations &&
        configuration.mixedOperationProbability > 0 &&
        _random.nextDouble() < configuration.mixedOperationProbability;
    if (mayGenerateMixed) {
      return _questionGenerator.generateMixedQuestion(
        difficulty: configuration.difficulty,
      );
    }
    final operations = configuration.operations.toList(growable: false);
    final operation = operations[_random.nextInt(operations.length)];
    return _questionGenerator.generateQuestion(
      difficulty: configuration.difficulty,
      operation: operation,
    );
  }

  void _finish(DateTime now) {
    _finishedAt = now;
    _closePausedInterval(now);
    _questionActiveSince = null;
    _state = SessionLifecycleState.completed;
  }

  void _closePausedInterval(DateTime now) {
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      _totalPaused += _nonNegative(now.difference(pausedAt));
      _pausedAt = null;
    }
  }

  Duration _elapsedAt(DateTime now) {
    final startedAt = _startedAt;
    if (startedAt == null) return Duration.zero;
    final end = _finishedAt ?? now;
    final pausedNow = _pausedAt == null
        ? Duration.zero
        : _nonNegative(end.difference(_pausedAt!));
    final elapsed =
        _nonNegative(end.difference(startedAt)) - _totalPaused - pausedNow;
    if (elapsed <= Duration.zero) return Duration.zero;
    return elapsed > configuration.duration ? configuration.duration : elapsed;
  }

  SessionResult _buildResult() => SessionResult(
    userId: _userId!,
    attempts: _attempts,
    elapsedTime: _elapsedAt(_finishedAt!),
  );

  void _requireState(SessionLifecycleState expected) {
    if (_state != expected) {
      throw StateError('Session is ${_state.name}, expected ${expected.name}.');
    }
  }

  static Duration _nonNegative(Duration duration) =>
      duration.isNegative ? Duration.zero : duration;

  static bool _sameAttempt(QuestionAttempt first, QuestionAttempt second) =>
      first.questionNumber == second.questionNumber &&
      first.expression == second.expression &&
      first.correctAnswer == second.correctAnswer &&
      first.selectedAnswer == second.selectedAnswer &&
      first.isCorrect == second.isCorrect &&
      first.operation == second.operation &&
      first.difficulty == second.difficulty;

  static Map<ArithmeticDifficulty, ArithmeticDifficultyConfig>
  _questionConfigurations(SessionConfiguration configuration) => {
    ...ArithmeticDifficultyConfig.defaults,
    configuration.difficulty: configuration.arithmeticConfiguration,
  };
}
