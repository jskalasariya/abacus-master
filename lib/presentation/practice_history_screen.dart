import 'package:flutter/material.dart';

import '../domain/arithmetic/arithmetic_operation.dart';
import '../domain/sessions/practice_history_models.dart';
import '../domain/sessions/practice_session_repository.dart';
import 'practice_screens.dart';

const _historyInk = Color(0xFF183538);
const _historyTeal = Color(0xFF168777);
const _historyMint = Color(0xFFE4F5EF);

class PracticeHistoryScreen extends StatefulWidget {
  const PracticeHistoryScreen({
    required this.repository,
    required this.userId,
    super.key,
  });

  final PracticeSessionRepository repository;
  final String userId;

  @override
  State<PracticeHistoryScreen> createState() => _PracticeHistoryScreenState();
}

class _PracticeHistoryScreenState extends State<PracticeHistoryScreen> {
  static const _pageSize = 20;
  final List<PracticeSessionSummary> _sessions = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String? _openingSessionId;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage({bool nextPage = false}) async {
    if (_loadingMore || (nextPage && !_hasMore)) return;
    setState(() {
      if (nextPage) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await widget.repository.listCompletedSessionSummaries(
        widget.userId,
        limit: _pageSize,
        offset: nextPage ? _sessions.length : 0,
      );
      if (!mounted) return;
      setState(() {
        if (!nextPage) _sessions.clear();
        _sessions.addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'Practice history could not be loaded. Please try again.';
      });
    }
  }

  Future<void> _openSession(PracticeSessionSummary summary) async {
    if (_openingSessionId != null) return;
    setState(() => _openingSessionId = summary.id);
    try {
      final session = await widget.repository.getSession(
        sessionId: summary.id,
        userId: widget.userId,
      );
      if (!mounted) return;
      if (session == null || session.result == null) {
        setState(() {
          _openingSessionId = null;
          _error = 'That completed session is not available for review.';
        });
        return;
      }
      setState(() => _openingSessionId = null);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PracticeResultsScreen(session: session),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _openingSessionId = null;
        _error = 'That session could not be opened. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Practice history')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _loadPage(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                    children: [
                      Text(
                        'Your practice sessions',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: _historyInk,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Open any finished test to review the answers you saved.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _HistoryNotice(
                          text: _error!,
                          onRetry: () => _loadPage(),
                        ),
                      ],
                      if (_sessions.isEmpty && _error == null)
                        const _HistoryEmptyState()
                      else ...[
                        const SizedBox(height: 18),
                        for (final session in _sessions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SessionSummaryCard(
                              summary: session,
                              opening: _openingSessionId == session.id,
                              onTap: () => _openSession(session),
                            ),
                          ),
                        if (_hasMore)
                          OutlinedButton.icon(
                            onPressed: _loadingMore
                                ? null
                                : () => _loadPage(nextPage: true),
                            icon: _loadingMore
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more_rounded),
                            label: Text(
                              _loadingMore ? 'Loading…' : 'Load more sessions',
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    ),
  );
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 64),
    child: Column(
      children: [
        const Icon(Icons.auto_stories_rounded, size: 58, color: _historyTeal),
        const SizedBox(height: 14),
        Text(
          'Your first result will show up here',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: _historyInk, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Finish a practice session to build your history.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({
    required this.summary,
    required this.opening,
    required this.onTap,
  });

  final PracticeSessionSummary summary;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final config = summary.configuration;
    final date = summary.completedAt.toLocal();
    final operations = config.operations.map(_operationName).join(' · ');
    final decimalSetting = config.decimalProbability <= 0
        ? 'Whole-number questions'
        : 'Decimals: ${config.allowedDecimalPlaces.map((places) => '$places places').join(', ')}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_dateLabel(date)} · ${_timeLabel(date)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _historyInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (opening)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '${_difficultyName(config.difficulty)} · ${summary.attemptedCount} questions · '
                '${summary.correctCount} correct · ${(summary.accuracy * 100).round()}% accuracy',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 7),
              Text('Time: ${_durationLabel(summary.elapsedTime)}'),
              const SizedBox(height: 4),
              Text(operations),
              const SizedBox(height: 4),
              Text(decimalSetting),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryNotice extends StatelessWidget {
  const _HistoryNotice({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFE8E2),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class PracticeStatisticsScreen extends StatefulWidget {
  const PracticeStatisticsScreen({
    required this.repository,
    required this.userId,
    super.key,
  });

  final PracticeSessionRepository repository;
  final String userId;

  @override
  State<PracticeStatisticsScreen> createState() =>
      _PracticeStatisticsScreenState();
}

class _PracticeStatisticsScreenState extends State<PracticeStatisticsScreen> {
  late Future<PracticeStatistics> _statistics;

  @override
  void initState() {
    super.initState();
    _statistics = widget.repository.getStatistics(widget.userId);
  }

  void _retry() {
    setState(
      () => _statistics = widget.repository.getStatistics(widget.userId),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My progress')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: FutureBuilder<PracticeStatistics>(
            future: _statistics,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Your progress could not be loaded.'),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final stats = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                children: [
                  Text(
                    'Your number skills',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _historyInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'These summaries use your completed tests and saved answers.',
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 560 ? 3 : 2;
                      final width =
                          (constraints.maxWidth - 12 * (columns - 1)) / columns;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _StatCard(
                            width: width,
                            label: 'Completed tests',
                            value: '${stats.completedTestCount}',
                          ),
                          _StatCard(
                            width: width,
                            label: 'Questions answered',
                            value: '${stats.totalAttemptedCount}',
                          ),
                          _StatCard(
                            width: width,
                            label: 'Overall accuracy',
                            value: '${(stats.overallAccuracy * 100).round()}%',
                            detail: 'Weighted by questions answered',
                          ),
                          _StatCard(
                            width: width,
                            label: 'Average test accuracy',
                            value:
                                '${(stats.averageTestAccuracy * 100).round()}%',
                            detail: 'Each completed test counts equally',
                          ),
                          _StatCard(
                            width: width,
                            label: 'Average answer time',
                            value: _durationLabel(stats.averageResponseTime),
                          ),
                          _StatCard(
                            width: width,
                            label: 'Best correct streak',
                            value: '${stats.bestCorrectAnswerStreak}',
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle(context, 'By operation'),
                  for (final operation in ArithmeticOperation.values)
                    _BreakdownRow(
                      title: _operationName(operation),
                      count: stats.byOperation[operation]!.attemptedCount,
                      accuracy: stats.byOperation[operation]!.accuracy,
                    ),
                  const SizedBox(height: 18),
                  _sectionTitle(context, 'By difficulty'),
                  for (final difficulty in ArithmeticDifficulty.values)
                    _BreakdownRow(
                      title: _difficultyName(difficulty),
                      count: stats.byDifficulty[difficulty]!.attemptedCount,
                      accuracy: stats.byDifficulty[difficulty]!.accuracy,
                      detail:
                          '${stats.byDifficulty[difficulty]!.completedTestCount} tests',
                    ),
                  const SizedBox(height: 18),
                  _sectionTitle(context, 'Recent progress'),
                  if (stats.recentProgress.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('Finish a test to see your progress here.'),
                    )
                  else
                    for (final point in stats.recentProgress)
                      _RecentProgressRow(point: point),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.label,
    required this.value,
    this.detail,
  });
  final double width;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      color: _historyMint,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 7),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900, color: _historyInk),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ),
  );
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.title,
    required this.count,
    required this.accuracy,
    this.detail,
  });
  final String title;
  final int count;
  final double accuracy;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text('$count tries · ${(accuracy * 100).round()}%'),
          ],
        ),
        if (detail != null)
          Text(detail!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: accuracy.clamp(0, 1),
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
          color: _historyTeal,
          backgroundColor: _historyMint,
        ),
      ],
    ),
  );
}

class _RecentProgressRow extends StatelessWidget {
  const _RecentProgressRow({required this.point});
  final PracticeProgressPoint point;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(_dateLabel(point.completedAt.toLocal())),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: point.accuracy.clamp(0, 1),
            minHeight: 10,
            borderRadius: BorderRadius.circular(10),
            color: _historyTeal,
            backgroundColor: _historyMint,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 88,
          child: Text(
            '${point.correctCount}/${point.attemptedCount} · ${(point.accuracy * 100).round()}%',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    ),
  );
}

Widget _sectionTitle(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    title,
    style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(color: _historyInk, fontWeight: FontWeight.w900),
  ),
);

String _difficultyName(ArithmeticDifficulty difficulty) => switch (difficulty) {
  ArithmeticDifficulty.beginner => 'Beginner',
  ArithmeticDifficulty.medium => 'Medium',
  ArithmeticDifficulty.advanced => 'Advanced',
};

String _operationName(ArithmeticOperation operation) => switch (operation) {
  ArithmeticOperation.addition => 'Addition',
  ArithmeticOperation.subtraction => 'Subtraction',
  ArithmeticOperation.multiplication => 'Multiplication',
  ArithmeticOperation.division => 'Division',
};

String _dateLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _timeLabel(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _durationLabel(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  return '${seconds ~/ 60}m ${(seconds % 60).toString().padLeft(2, '0')}s';
}
