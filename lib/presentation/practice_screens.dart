import 'dart:async';

import 'package:flutter/material.dart';

import '../application/practice_session_coordinator.dart';
import '../domain/arithmetic/arithmetic_operation.dart';
import '../domain/arithmetic/multiple_choice_option_generator.dart';
import '../domain/arithmetic/rational.dart';
import '../domain/answer_feedback_mode.dart';
import '../domain/sessions/practice_session.dart';
import '../domain/sessions/practice_session_repository.dart';
import '../domain/sessions/session_configuration.dart';
import '../domain/sessions/session_models.dart';

typedef StartPractice = Future<PracticeSessionCoordinator> Function(
  SessionConfiguration configuration,
);

const _teal = Color(0xFF168777);
const _ink = Color(0xFF183538);
const _mint = Color(0xFFE4F5EF);
const _gold = Color(0xFFFFCB62);
const _coral = Color(0xFFFFE8E2);

class PracticeConfigurationScreen extends StatefulWidget {
  const PracticeConfigurationScreen({
    required this.onStart,
    required this.initialFeedbackMode,
    this.initialDifficulty = ArithmeticDifficulty.beginner,
    this.initialDecimalPrecision = 0,
    this.quickTest = false,
    super.key,
  }) : assert(initialDecimalPrecision >= 0 && initialDecimalPrecision <= 3);

  final StartPractice onStart;
  final AnswerFeedbackMode initialFeedbackMode;
  final ArithmeticDifficulty initialDifficulty;
  final int initialDecimalPrecision;
  final bool quickTest;

  @override
  State<PracticeConfigurationScreen> createState() =>
      _PracticeConfigurationScreenState();
}

class _PracticeConfigurationScreenState
    extends State<PracticeConfigurationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _questionCount;
  late final TextEditingController _durationMinutes;
  late ArithmeticDifficulty _difficulty;
  final Set<ArithmeticOperation> _operations = ArithmeticOperation.values
      .toSet();
  late Set<int> _decimalPlaces;
  late bool _includeDecimals;
  bool _includeMixed = false;
  late AnswerFeedbackMode _feedbackMode;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _difficulty = widget.initialDifficulty;
    _includeDecimals = widget.initialDecimalPrecision > 0;
    _decimalPlaces = {
      widget.initialDecimalPrecision == 0 ? 1 : widget.initialDecimalPrecision,
    };
    _feedbackMode = widget.initialFeedbackMode;
    _questionCount = TextEditingController(
      text: widget.quickTest ? '10' : '100',
    );
    _durationMinutes = TextEditingController(
      text: widget.quickTest ? '1' : '10',
    );
  }

  @override
  void dispose() {
    _questionCount.dispose();
    _durationMinutes.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    if (_operations.isEmpty) {
      setState(() => _error = 'Choose at least one operation.');
      return;
    }
    if (_includeDecimals && _decimalPlaces.isEmpty) {
      setState(() => _error = 'Choose at least one decimal place.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = SessionConfiguration(
        difficulty: _difficulty,
        questionCount: int.parse(_questionCount.text),
        duration: Duration(minutes: int.parse(_durationMinutes.text)),
        operations: _operations,
        decimalProbability: _includeDecimals ? 0.25 : 0,
        allowedDecimalPlaces: _includeDecimals
            ? (_decimalPlaces.toList()..sort())
            : const [1],
        allowMixedOperations: _includeMixed,
        mixedOperationProbability: _includeMixed ? 0.2 : 0,
        answerFeedbackMode: _feedbackMode,
      );
      final coordinator = await widget.onStart(config);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LivePracticeScreen(
            coordinator: coordinator,
            quickTest: widget.quickTest,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.quickTest ? 'Quick Test' : 'Practice')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  Text(
                    'Make it your kind of practice!',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900, color: _ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a level and a few number skills to warm up.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  _SectionCard(
                    title: 'Difficulty',
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: ArithmeticDifficulty.values.map((level) {
                        final selected = level == _difficulty;
                        return ChoiceChip(
                          label: Text(_difficultyLabel(level)),
                          selected: selected,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _difficulty = level),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Your session',
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final fields = [
                          _numberField(
                            controller: _questionCount,
                            label: 'Questions',
                            min: 1,
                            max: SessionConfiguration.maxQuestionCount,
                            suffix: 'questions',
                          ),
                          _numberField(
                            controller: _durationMinutes,
                            label: 'Time',
                            min: 1,
                            max: 1440,
                            suffix: 'minutes',
                          ),
                        ];
                        if (constraints.maxWidth < 440) {
                          return Column(
                            children: [
                              fields[0],
                              const SizedBox(height: 12),
                              fields[1],
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: fields[0]),
                            const SizedBox(width: 14),
                            Expanded(child: fields[1]),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Operations',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: ArithmeticOperation.values.map((operation) {
                        return FilterChip(
                          label: Text(_operationLabel(operation)),
                          selected: _operations.contains(operation),
                          onSelected: _busy
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    _operations.add(operation);
                                  } else {
                                    _operations.remove(operation);
                                    if (_includeMixed &&
                                        const {
                                          ArithmeticOperation.addition,
                                          ArithmeticOperation.subtraction,
                                          ArithmeticOperation.multiplication,
                                        }.contains(operation)) {
                                      _includeMixed = false;
                                    }
                                  }
                                }),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Number twists',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Include decimal questions'),
                          value: _includeDecimals,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _includeDecimals = value),
                        ),
                        if (_includeDecimals) ...[
                          const Text('Decimal places'),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [1, 2, 3].map((places) {
                              return FilterChip(
                                label: Text(
                                  '$places place${places == 1 ? '' : 's'}',
                                ),
                                selected: _decimalPlaces.contains(places),
                                onSelected: _busy
                                    ? null
                                    : (selected) => setState(() {
                                        if (selected) {
                                          _decimalPlaces.add(places);
                                        } else {
                                          _decimalPlaces.remove(places);
                                        }
                                      }),
                              );
                            }).toList(),
                          ),
                        ],
                        const Divider(height: 24),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Mix addition, subtraction and multiplication',
                          ),
                          subtitle: const Text(
                            'A little extra challenge, now and then',
                          ),
                          value: _includeMixed,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  _includeMixed = value;
                                  if (value) {
                                    _operations.addAll(const {
                                      ArithmeticOperation.addition,
                                      ArithmeticOperation.subtraction,
                                      ArithmeticOperation.multiplication,
                                    });
                                  }
                                }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Answer feedback',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('When would you like to see the answers?'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ChoiceChip(
                              label: const Text('After each answer'),
                              selected:
                                  _feedbackMode == AnswerFeedbackMode.immediate,
                              onSelected: _busy
                                  ? null
                                  : (_) => setState(
                                      () => _feedbackMode =
                                          AnswerFeedbackMode.immediate,
                                    ),
                            ),
                            ChoiceChip(
                              label: const Text('At the end of the test'),
                              selected:
                                  _feedbackMode == AnswerFeedbackMode.endOfTest,
                              onSelected: _busy
                                  ? null
                                  : (_) => setState(
                                      () => _feedbackMode =
                                          AnswerFeedbackMode.endOfTest,
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'This choice is just for this test and will not change your saved profile setting.',
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _MessageBox(message: _error!, isError: true),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _start,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(_busy ? 'Getting ready…' : 'Start practising'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                      backgroundColor: _teal,
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required int min,
    required int max,
    required String suffix,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix,
      border: const OutlineInputBorder(),
    ),
    validator: (value) {
      final parsed = int.tryParse(value?.trim() ?? '');
      if (parsed == null || parsed < min || parsed > max) {
        return 'Choose $min to $max.';
      }
      return null;
    },
  );
}

class LivePracticeScreen extends StatefulWidget {
  const LivePracticeScreen({
    required this.coordinator,
    this.quickTest = false,
    this.feedbackDelay = const Duration(milliseconds: 900),
    this.wait,
    super.key,
  });

  final PracticeSessionCoordinator coordinator;
  final bool quickTest;
  final Duration feedbackDelay;
  final Future<void> Function(Duration duration)? wait;

  @override
  State<LivePracticeScreen> createState() => _LivePracticeScreenState();
}

class _LivePracticeScreenState extends State<LivePracticeScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  QuestionAttempt? _feedback;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _showingResults = false;
  bool _pendingAdvance = false;

  PracticeSessionCoordinator get coordinator => widget.coordinator;
  SessionQuestion? get question => coordinator.currentQuestion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    _loadQuestion();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  Future<void> _loadQuestion() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await coordinator.nextQuestion();
      if (!mounted) return;
      if (next == null &&
          coordinator.state == SessionLifecycleState.completed) {
        await _openResults();
        return;
      }
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _loading = false;
      });
    }
  }

  Future<void> _submit(ArithmeticAnswerOption option) async {
    if (_submitting ||
        _feedback != null ||
        coordinator.state != SessionLifecycleState.running) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final attempt = await coordinator.submitAnswer(option.value);
      if (!mounted) return;
      setState(() => _submitting = false);
      if (coordinator.state == SessionLifecycleState.completed) {
        await _openResults();
        return;
      }
      if (coordinator.configuration.answerFeedbackMode ==
          AnswerFeedbackMode.immediate) {
        setState(() => _feedback = attempt);
        await (widget.wait ?? _defaultWait)(widget.feedbackDelay);
        if (!mounted) return;
        if (coordinator.state == SessionLifecycleState.paused) {
          setState(() => _pendingAdvance = true);
          return;
        }
      }
      await _advance();
    } catch (error, stackTrace) {
      if (!mounted) return;
      debugPrint(
        'Practice answer submission failed (${error.runtimeType}): $error\n$stackTrace',
      );
      setState(() {
        _error = 'We could not save that answer. Your question is still here; please try again.';
        _submitting = false;
      });
    }
  }

  Future<void> _tick() async {
    if (!mounted || _showingResults) return;
    try {
      await coordinator.synchronize();
      if (!mounted) return;
      setState(() {});
      if (coordinator.state == SessionLifecycleState.completed &&
          _feedback == null) {
        await _openResults();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _advance() async {
    if (coordinator.state == SessionLifecycleState.completed) {
      await _openResults();
      return;
    }
    setState(() {
      _feedback = null;
      _pendingAdvance = false;
      _loading = true;
    });
    await _loadQuestion();
  }

  Future<void> _goPrevious() async {
    if (_submitting || _feedback != null) return;
    try {
      final previous = await coordinator.previousQuestion();
      if (mounted && previous != null) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _goNextPresented() async {
    if (_submitting || _feedback != null) return;
    try {
      final next = await coordinator.nextQuestion();
      if (mounted && next != null) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _togglePause() async {
    try {
      if (coordinator.state == SessionLifecycleState.paused) {
        await coordinator.resume();
      } else {
        await coordinator.pause();
      }
      if (mounted) setState(() => _error = null);
      if (mounted &&
          coordinator.state == SessionLifecycleState.running &&
          _pendingAdvance) {
        await _advance();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _confirmCancel() async {
    if (_showingResults) return;
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this session?'),
        content: const Text(
          'Your saved answers will stay in your results. This session will end here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep practising'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (cancel != true || !mounted) return;
    try {
      await coordinator.cancel();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _openResults() async {
    if (_showingResults || !mounted) return;
    _showingResults = true;
    _timer?.cancel();
    try {
      await coordinator.synchronize();
      final session = await coordinator.getPersistedSession();
      if (!mounted) return;
      if (session == null || session.result == null) {
        _showingResults = false;
        _timer = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => _tick(),
        );
        setState(() => _error = 'Your results are not ready to view yet.');
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PracticeResultsScreen(session: session),
        ),
      );
    } catch (error) {
      _showingResults = false;
      if (!mounted) return;
      _timer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _tick(),
      );
      setState(() => _error = _friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = question;
    final paused = coordinator.state == SessionLifecycleState.paused;
    final terminal = coordinator.state == SessionLifecycleState.completed;
    final progressNumber = current?.number ?? coordinator.attemptedCount;
    final seconds = coordinator.remainingTime.inSeconds;
    final remaining =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.quickTest ? 'Quick Test' : 'Practice'),
          leading: IconButton(
            tooltip: 'End session',
            onPressed: _confirmCancel,
            icon: const Icon(Icons.close_rounded),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Semantics(
                label: paused ? 'Session paused' : 'Time remaining $remaining',
                child: Chip(
                  avatar: Icon(
                    paused ? Icons.pause_rounded : Icons.timer_outlined,
                    color: _ink,
                  ),
                  label: Text(paused ? 'Paused' : remaining),
                  backgroundColor: _gold,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Semantics(
                    label:
                        'Question $progressNumber '
                        'of ${coordinator.configuration.questionCount}',
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value:
                                progressNumber /
                                coordinator.configuration.questionCount,
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(10),
                            color: _teal,
                            backgroundColor: _mint,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$progressNumber/${coordinator.configuration.questionCount}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    _MessageBox(message: _error!, isError: true),
                    const SizedBox(height: 14),
                  ],
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_feedback != null)
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: _feedback!.isCorrect ? _mint : _coral,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _feedback!.isCorrect
                                ? Icons.stars_rounded
                                : Icons.favorite_rounded,
                            size: 42,
                            color: _teal,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _feedback!.isCorrect
                                ? 'That’s right!'
                                : 'Good try! Keep going.',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          if (!_feedback!.isCorrect) ...[
                            const SizedBox(height: 6),
                            Text(
                              'The answer was ${_feedback!.correctAnswer.toExactString()}.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                          const SizedBox(height: 8),
                          const Text('Next question coming up…'),
                        ],
                      ),
                    )
                  else if (current != null)
                    _QuestionPanel(
                      question: current,
                      selectedAnswer: coordinator
                          .attemptForQuestion(current.number)
                          ?.selectedAnswer,
                      revealCorrectAnswer:
                          coordinator.configuration.answerFeedbackMode ==
                          AnswerFeedbackMode.immediate,
                      enabled: !paused && !_submitting && !terminal,
                      onAnswer: _submit,
                    )
                  else if (terminal)
                    const _FeedbackPanel(completed: true),
                  const SizedBox(height: 16),
                  if (current != null && current.number > 1) ...[
                    OutlinedButton.icon(
                      onPressed: paused || _submitting || _feedback != null
                          ? null
                          : _goPrevious,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Previous question'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    if (current.number <
                        coordinator.presentedQuestionCount) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: paused || _submitting || _feedback != null
                            ? null
                            : _goNextPresented,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Next question'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: terminal ? null : _togglePause,
                    icon: Icon(
                      paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    ),
                    label: Text(paused ? 'Resume session' : 'Pause session'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _defaultWait(Duration duration) =>
      Future<void>.delayed(duration);
}

class _QuestionPanel extends StatelessWidget {
  const _QuestionPanel({
    required this.question,
    required this.selectedAnswer,
    required this.revealCorrectAnswer,
    required this.enabled,
    required this.onAnswer,
  });

  final SessionQuestion question;
  final Rational? selectedAnswer;
  final bool revealCorrectAnswer;
  final bool enabled;
  final ValueChanged<ArithmeticAnswerOption> onAnswer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE5ECE9)),
          ),
          child: Column(
            children: [
              Text(
                'Question ${question.number}',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800, color: _teal),
              ),
              const SizedBox(height: 14),
              Semantics(
                label: 'Solve ${question.expression}',
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    question.expression,
                    style: Theme.of(context).textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w900, color: _ink),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Tap the answer you think is right'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 620 ? 4 : 2;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: columns == 4 ? 1.8 : 1.5,
              children: question.options.map((option) {
                return Semantics(
                  button: true,
                  label: 'Answer ${option.text}',
                  child: FilledButton(
                    onPressed: enabled ? () => onAnswer(option) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: option.value == selectedAnswer
                          ? (revealCorrectAnswer && option.isCorrect
                                ? _mint
                                : const Color(0xFFFFE8A8))
                          : const Color(0xFFE9F5F1),
                      foregroundColor: _ink,
                      disabledBackgroundColor: const Color(0xFFE9F5F1),
                      disabledForegroundColor: _ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: Text(option.text),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _mint,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.flag_rounded, size: 42, color: _teal),
          const SizedBox(height: 10),
          Text(
            completed ? 'Session complete!' : 'Time is up!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class PracticeResultsScreen extends StatelessWidget {
  const PracticeResultsScreen({required this.session, super.key});

  final PersistedPracticeSession session;

  @override
  Widget build(BuildContext context) {
    final result = session.result!;
    return Scaffold(
      appBar: AppBar(title: const Text('Your results')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
              children: [
                Text(
                  'Look what you did!',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'A little practice adds up to big brain power.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 620 ? 3 : 2;
                    final metrics = <(String, String, IconData)>[
                      (
                        'Correct',
                        '${result.correctCount}',
                        Icons.check_circle_rounded,
                      ),
                      (
                        'Incorrect',
                        '${result.incorrectCount}',
                        Icons.refresh_rounded,
                      ),
                      (
                        'Attempted',
                        '${result.attemptedCount}',
                        Icons.edit_note_rounded,
                      ),
                      (
                        'Accuracy',
                        '${(result.accuracy * 100).round()}%',
                        Icons.track_changes_rounded,
                      ),
                      (
                        'Elapsed',
                        _formatDuration(result.elapsedTime),
                        Icons.timer_outlined,
                      ),
                      (
                        'Average answer',
                        _formatDuration(result.averageResponseTime),
                        Icons.speed_rounded,
                      ),
                      (
                        'Best streak',
                        '${result.bestCorrectAnswerStreak}',
                        Icons.local_fire_department_rounded,
                      ),
                    ];
                    return GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: columns == 3 ? 2.15 : 1.6,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: metrics.map((metric) {
                        return _MetricCard(
                          label: metric.$1,
                          value: metric.$2,
                          icon: metric.$3,
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 22),
                Text(
                  'Question review',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                if (session.attempts.isEmpty)
                  const _MessageBox(
                    message: 'No answers were submitted in this session.',
                    isError: false,
                  )
                else
                  ...session.attempts.map(
                    (attempt) => _AttemptReviewTile(attempt: attempt),
                  ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Back to home'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: _teal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: _teal, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AttemptReviewTile extends StatelessWidget {
  const _AttemptReviewTile({required this.attempt});

  final QuestionAttempt attempt;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: attempt.isCorrect ? _mint : _coral,
        child: Icon(
          attempt.isCorrect ? Icons.check_rounded : Icons.close_rounded,
          color: attempt.isCorrect ? _teal : const Color(0xFFC45543),
        ),
      ),
      title: Text(
        '${attempt.questionNumber}.  ${attempt.expression}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        'Your answer: ${attempt.selectedAnswer.toExactString()}   •   '
        'Correct answer: ${attempt.correctAnswer.toExactString()}',
      ),
      isThreeLine: true,
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE5ECE9)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isError ? _coral : _mint,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Semantics(liveRegion: true, child: Text(message)),
  );
}

String _operationLabel(ArithmeticOperation operation) => switch (operation) {
  ArithmeticOperation.addition => 'Addition +',
  ArithmeticOperation.subtraction => 'Subtraction −',
  ArithmeticOperation.multiplication => 'Multiplication ×',
  ArithmeticOperation.division => 'Division ÷',
};

String _difficultyLabel(ArithmeticDifficulty difficulty) =>
    switch (difficulty) {
      ArithmeticDifficulty.beginner => 'Beginner',
      ArithmeticDifficulty.medium => 'Medium',
      ArithmeticDifficulty.advanced => 'Advanced',
    };

String _friendlyError(Object error) {
  if (error is UnauthenticatedSessionException) {
    return 'Please sign in again before starting this session.';
  }
  if (error is SessionOwnerChangedException) {
    return 'Your profile changed. This session was safely ended.';
  }
  if (error is PracticeSessionRepositoryException) return error.message;
  return 'Something went wrong saving your practice. Please try again.';
}

String _formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  return '${seconds ~/ 60}m ${(seconds % 60).toString().padLeft(2, '0')}s';
}
