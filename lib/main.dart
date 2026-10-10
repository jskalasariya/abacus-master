import 'dart:async';

import 'package:flutter/material.dart';

import 'application/authentication_controller.dart';
import 'application/practice_session_coordinator.dart';
import 'domain/profiles/user_profile.dart';
import 'domain/sessions/session_configuration.dart';
import 'presentation/authentication_screens.dart';
import 'presentation/practice_screens.dart';
import 'presentation/profile_settings_screen.dart';
import 'presentation/practice_history_screen.dart';

const _ink = Color(0xFF183538);
const _teal = Color(0xFF168777);
const _mint = Color(0xFFE4F5EF);
const _coral = Color(0xFFFF876F);
const _gold = Color(0xFFFFCB62);
const _canvas = Color(0xFFF7FAF8);

void main() {
  runApp(const AbacusMasterApp());
}

class AbacusMasterApp extends StatelessWidget {
  const AbacusMasterApp({super.key, this.controllerFactory});

  final AuthenticationControllerFactory? controllerFactory;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _teal,
      brightness: Brightness.light,
      surface: _canvas,
    );

    return MaterialApp(
      title: 'Abacus Master',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _canvas,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: _ink,
          displayColor: _ink,
        ),
      ),
      home: _AuthenticationRoot(
        controllerFactory: controllerFactory ?? AuthenticationController.open,
      ),
    );
  }
}

class _AuthenticationRoot extends StatefulWidget {
  const _AuthenticationRoot({required this.controllerFactory});

  final AuthenticationControllerFactory controllerFactory;

  @override
  State<_AuthenticationRoot> createState() => _AuthenticationRootState();
}

class _AuthenticationRootState extends State<_AuthenticationRoot> {
  AuthenticationController? _controller;
  List<UserProfile> _profiles = const [];
  bool _loading = true;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _startupError = null;
      });
    }
    AuthenticationController? createdController;
    try {
      createdController = await widget.controllerFactory();
      final profiles = await createdController.loadProfiles();
      await createdController.recoverInterruptedSessions();
      if (!mounted) {
        unawaited(createdController.close());
        return;
      }
      createdController.addListener(_onAuthenticationChanged);
      setState(() {
        _controller = createdController;
        _profiles = profiles;
        _loading = false;
      });
    } catch (_) {
      if (createdController != null) unawaited(createdController.close());
      if (!mounted) return;
      setState(() {
        _startupError = 'We couldn’t open local profiles. Please try again.';
        _loading = false;
      });
    }
  }

  void _onAuthenticationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onAuthenticationChanged);
      unawaited(controller.close());
    }
    super.dispose();
  }

  Future<void> _refreshProfiles() async {
    final profiles = await _controller!.loadProfiles();
    if (mounted) setState(() => _profiles = profiles);
  }

  void _openCreateProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateProfileScreen(
          onCreate: (username, password) => _controller!.createProfile(
            username: username,
            password: password,
          ),
          onCreated: (profile) async {
            await _refreshProfiles();
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => LoginScreen(
                  initialUsername: profile.username,
                  notice: 'Profile created. Sign in to start practising.',
                  onLogin: (username, password) => _controller!.login(
                    username: username,
                    password: password,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openLogin(String username) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          initialUsername: username,
          onLogin: (enteredUsername, password) =>
              _controller!.login(username: enteredUsername, password: password),
        ),
      ),
    );
  }

  void _openProfileSelector() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => WelcomeScreen(
          profiles: _profiles,
          onCreateProfile: _openCreateProfile,
          onLogin: _openLogin,
          onCancel: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  Future<void> _openPractice({bool quickTest = false}) async {
    final controller = _controller;
    if (controller == null || !controller.isAuthenticated) return;
    UserSettings settings;
    try {
      settings =
          await controller.loadActiveSettings() ??
          UserSettings(userId: controller.activeUserId!);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load your saved settings.')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeConfigurationScreen(
          quickTest: quickTest,
          initialDifficulty: settings.difficulty,
          initialDecimalPrecision: settings.decimalPrecision,
          initialFeedbackMode: settings.answerFeedbackMode,
          onStart: _createPracticeSession,
        ),
      ),
    );
  }

  Future<void> _openProfileSettings() async {
    final controller = _controller;
    if (controller == null || !controller.isAuthenticated) return;
    try {
      final settings = await controller.loadActiveSettings();
      if (!mounted || settings == null) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileSettingsScreen(
            initialSettings: settings,
            onSave: controller.saveActiveSettings,
            onChangePassword: controller.changeActivePassword,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open profile settings.')),
        );
      }
    }
  }

  void _openPracticeHistory() {
    final controller = _controller;
    final userId = controller?.activeUserId;
    if (controller == null || userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeHistoryScreen(
          repository: controller.practiceSessions,
          userId: userId,
        ),
      ),
    );
  }

  void _openPracticeStatistics() {
    final controller = _controller;
    final userId = controller?.activeUserId;
    if (controller == null || userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeStatisticsScreen(
          repository: controller.practiceSessions,
          userId: userId,
        ),
      ),
    );
  }

  Future<PracticeSessionCoordinator> _createPracticeSession(
    SessionConfiguration configuration,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.isAuthenticated) {
      throw const UnauthenticatedSessionException();
    }
    final coordinator = PracticeSessionCoordinator(
      configuration: configuration,
      authenticatedUserId: () => _controller?.activeUserId,
      repository: controller.practiceSessions,
    );
    await coordinator.start();
    return coordinator;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Semantics(
            label: 'Opening local profiles',
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    if (_startupError != null || _controller == null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _startupError ?? 'Local profiles are unavailable.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _initialize,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final controller = _controller!;
    final activeProfile = controller.activeProfile;
    if (activeProfile != null) {
      return HomeScreen(
        profile: activeProfile,
        onSwitchProfile: _openProfileSelector,
        onLogout: controller.logout,
        onPractice: () => _openPractice(),
        onQuickTest: () => _openPractice(quickTest: true),
        onOpenSettings: _openProfileSettings,
        onOpenHistory: _openPracticeHistory,
        onOpenStatistics: _openPracticeStatistics,
      );
    }
    return WelcomeScreen(
      profiles: _profiles,
      onCreateProfile: _openCreateProfile,
      onLogin: _openLogin,
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.profile,
    required this.onSwitchProfile,
    required this.onLogout,
    required this.onPractice,
    required this.onQuickTest,
    required this.onOpenSettings,
    required this.onOpenHistory,
    required this.onOpenStatistics,
    super.key,
  });

  final UserProfile profile;
  final VoidCallback onSwitchProfile;
  final VoidCallback onLogout;
  final VoidCallback onPractice;
  final VoidCallback onQuickTest;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenStatistics;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final contentPadding = wide ? 36.0 : 20.0;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    contentPadding,
                    wide ? 30 : 22,
                    contentPadding,
                    32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: 16),
                      _AccountControls(
                        username: profile.username,
                        onSwitchProfile: onSwitchProfile,
                        onLogout: onLogout,
                        onOpenSettings: onOpenSettings,
                      ),
                      SizedBox(height: wide ? 34 : 28),
                      _WelcomeBanner(wide: wide, onStart: onPractice),
                      const SizedBox(height: 30),
                      Text(
                        'Pick your next step',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, gridConstraints) {
                          final columns = gridConstraints.maxWidth >= 850
                              ? 4
                              : gridConstraints.maxWidth >= 540
                              ? 2
                              : 2;
                          final ratio = gridConstraints.maxWidth < 300
                              ? 0.58
                              : gridConstraints.maxWidth < 340
                              ? 0.7
                              : gridConstraints.maxWidth < 540
                              ? 1.1
                              : gridConstraints.maxWidth >= 850
                              ? 1.5
                              : 1.42;

                          return GridView.count(
                            crossAxisCount: columns,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: ratio,
                            children: [
                              _HomeActionCard(
                                title: 'Quick Test',
                                description: 'A little number challenge',
                                icon: Icons.bolt_rounded,
                                color: const Color(0xFFFFF0D5),
                                iconColor: const Color(0xFFB66A00),
                                onTap: onQuickTest,
                              ),
                              _HomeActionCard(
                                title: 'Practice',
                                description: 'Build skills one step at a time',
                                icon: Icons.sports_esports_rounded,
                                color: const Color(0xFFE3F4EF),
                                iconColor: _teal,
                                onTap: onPractice,
                              ),
                              _HomeActionCard(
                                title: 'My Progress',
                                description: 'See how far you have come',
                                icon: Icons.emoji_events_rounded,
                                color: const Color(0xFFFFE8E2),
                                iconColor: const Color(0xFFC45543),
                                onTap: onOpenStatistics,
                              ),
                              _HomeActionCard(
                                title: 'History',
                                description: 'Review finished practice',
                                icon: Icons.history_rounded,
                                color: const Color(0xFFE5F0FF),
                                iconColor: const Color(0xFF386FA4),
                                onTap: onOpenHistory,
                              ),
                              _HomeActionCard(
                                title: 'Profiles',
                                description: 'A space for every learner',
                                icon: Icons.face_rounded,
                                color: const Color(0xFFECE8FF),
                                iconColor: const Color(0xFF6653B5),
                                onTap: onSwitchProfile,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 26),
                      const _LevelGuide(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _gold,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.calculate_rounded, color: _ink, size: 28),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Abacus Master',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Small steps. Brilliant minds.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: const Color(0xFF617578)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.wide, required this.onStart});

  final bool wide;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _teal,
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: wide ? 60 : -40,
            top: -82,
            child: Container(
              width: 230,
              height: 230,
              decoration: const BoxDecoration(
                color: Color(0xFF249A87),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(wide ? 30 : 22),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Text(
                          'READY, SET, GROW!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 17),
                      Text(
                        'Every number\nhas a superpower.',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                              letterSpacing: -0.8,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Warm up your brain and make those number skills shine.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onStart,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start Practising'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: _ink,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 15,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (wide) ...[
                  const SizedBox(width: 18),
                  const Expanded(child: _AbacusIllustration()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AbacusIllustration extends StatelessWidget {
  const _AbacusIllustration();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9E9),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33133F3A),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _AbacusBead(color: _coral),
                _AbacusBead(color: _gold),
                _AbacusBead(color: Color(0xFF8E80D9)),
                _AbacusBead(color: _teal),
                _AbacusBead(color: _coral),
              ],
            ),
            const SizedBox(height: 10),
            Container(height: 8, decoration: _abacusBar),
            const SizedBox(height: 14),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _AbacusBead(color: _gold),
                _AbacusBead(color: _teal),
                _AbacusBead(color: _coral),
                _AbacusBead(color: Color(0xFF8E80D9)),
                _AbacusBead(color: _gold),
              ],
            ),
            const SizedBox(height: 10),
            Container(height: 8, decoration: _abacusBar),
            const SizedBox(height: 13),
            const Text(
              '1 + 2 + 3 = ?',
              style: TextStyle(
                color: _ink,
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _abacusBar = BoxDecoration(
  color: Color(0xFF4C4135),
  borderRadius: BorderRadius.all(Radius.circular(10)),
);

class _AbacusBead extends StatelessWidget {
  const _AbacusBead({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 29,
      height: 29,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFE5ECE9)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: iconColor, size: compact ? 22 : 25),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        (compact
                                ? Theme.of(context).textTheme.titleSmall
                                : Theme.of(context).textTheme.titleMedium)
                            ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF637578),
                      height: 1.25,
                      fontSize: compact ? 12 : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelGuide extends StatelessWidget {
  const _LevelGuide();

  @override
  Widget build(BuildContext context) {
    const levels = [
      ('Beginner', Color(0xFFDEF2E9), Color(0xFF257252)),
      ('Medium', Color(0xFFFFF0D5), Color(0xFF956000)),
      ('Advanced', Color(0xFFECE8FF), Color(0xFF6653B5)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _mint,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        spacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Levels to explore',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                'Choose a challenge that feels right for you.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: const Color(0xFF55706D)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, background, foreground) in levels)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountControls extends StatelessWidget {
  const _AccountControls({
    required this.username,
    required this.onSwitchProfile,
    required this.onLogout,
    required this.onOpenSettings,
  });

  final String username;
  final VoidCallback onSwitchProfile;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE5ECE9)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final account = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_circle_rounded, color: _teal),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    'Practising as $username',
                    softWrap: true,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
            final actions = Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Settings'),
                ),
                TextButton.icon(
                  onPressed: onSwitchProfile,
                  icon: const Icon(Icons.switch_account_rounded),
                  label: const Text('Switch profile'),
                ),
                TextButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
              ],
            );

            if (constraints.maxWidth < 440) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [account, actions],
              );
            }
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 12,
              children: [account, actions],
            );
          },
        ),
      ),
    );
  }
}

class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({required this.feature, super.key});

  final String feature;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(feature)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 56, color: _teal),
              const SizedBox(height: 18),
              Text(
                '$feature is coming next!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'We are getting this ready for you. Check back soon!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
