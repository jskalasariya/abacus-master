import 'package:flutter/material.dart';

import '../application/authentication_service.dart';
import '../domain/profiles/profile_input_rules.dart';
import '../domain/profiles/profile_repository.dart';
import '../domain/profiles/user_profile.dart';

typedef ProfileLoginHandler = Future<void> Function(
  String username,
  String password,
);

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    required this.profiles,
    required this.onCreateProfile,
    required this.onLogin,
    this.onCancel,
    super.key,
  });

  final List<UserProfile> profiles;
  final VoidCallback onCreateProfile;
  final ValueChanged<String> onLogin;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final isFirstRun = profiles.isEmpty;
    return _AuthPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AuthBrand(),
          const SizedBox(height: 34),
          Text(
            isFirstRun ? 'Let’s get started!' : 'Who is practising today?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            isFirstRun
                ? 'Create a learner profile to begin your number adventure.'
                : 'Choose a profile, then enter its password to continue.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 26),
          if (profiles.isNotEmpty) ...[
            for (final profile in profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: Colors.white,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE4F5EF),
                      child: Text(
                        profile.username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text(
                      profile.username,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('Sign in to this profile'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => onLogin(profile.username),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onLogin(''),
              icon: const Icon(Icons.person_search_rounded),
              label: const Text('Log in with another username'),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: onCreateProfile,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(isFirstRun ? 'Create first profile' : 'Add a profile'),
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onCancel, child: const Text('Back to home')),
          ],
        ],
      ),
    );
  }
}

class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({
    required this.onCreate,
    required this.onCreated,
    super.key,
  });

  final Future<UserProfile> Function(String username, String password) onCreate;
  final Future<void> Function(UserProfile profile) onCreated;

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await widget.onCreate(
        ProfileInputRules.normalizeUsername(_usernameController.text)!,
        _passwordController.text,
      );
      await widget.onCreated(profile);
    } on DuplicateUsernameException {
      if (mounted) {
        setState(() => _error = 'That username is already taken. Try another.');
      }
    } on InvalidAuthenticationInputException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We couldn’t create that profile. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthPage(
      title: 'Create a profile',
      subtitle: 'Choose a name and password for your learner.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _usernameField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              validator: (value) {
                if (ProfileInputRules.normalizeUsername(value ?? '') == null) {
                  return 'Use 3–24 letters, numbers, or underscores.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              visible: _passwordVisible,
              onVisibilityChanged: (visible) =>
                  setState(() => _passwordVisible = visible),
              label: 'Password',
              hint: 'At least 8 characters',
              autofillHint: AutofillHints.newPassword,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _confirmFocus.requestFocus(),
              validator: (value) =>
                  ProfileInputRules.isValidPassword(value ?? '')
                  ? null
                  : 'Use between 8 and 128 characters.',
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: _confirmController,
              focusNode: _confirmFocus,
              visible: _confirmVisible,
              onVisibilityChanged: (visible) =>
                  setState(() => _confirmVisible = visible),
              label: 'Confirm password',
              hint: 'Type the password again',
              autofillHint: AutofillHints.newPassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              validator: (value) => value == _passwordController.text
                  ? null
                  : 'The passwords don’t match.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorMessage(_error!),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const _ButtonProgress()
                  : const Text('Create profile'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.onLogin,
    this.initialUsername = '',
    this.notice,
    super.key,
  });

  final ProfileLoginHandler onLogin;
  final String initialUsername;
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _passwordVisible = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.initialUsername);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onLogin(
        ProfileInputRules.normalizeUsername(_usernameController.text)!,
        _passwordController.text,
      );
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on LoginFailedException {
      if (mounted) {
        setState(() => _error = 'We couldn’t sign in with those details.');
      }
    } on InvalidAuthenticationInputException {
      if (mounted) {
        setState(() => _error = 'We couldn’t sign in with those details.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Sign-in is unavailable right now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthPage(
      title: 'Welcome back',
      subtitle: 'Sign in to keep practising.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.notice != null) ...[
              _NoticeMessage(widget.notice!),
              const SizedBox(height: 16),
            ],
            _usernameField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              validator: (value) =>
                  ProfileInputRules.normalizeUsername(value ?? '') == null
                  ? 'Enter a valid username.'
                  : null,
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              visible: _passwordVisible,
              onVisibilityChanged: (visible) =>
                  setState(() => _passwordVisible = visible),
              label: 'Password',
              hint: 'Enter your password',
              autofillHint: AutofillHints.password,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              validator: (value) =>
                  ProfileInputRules.isValidPassword(value ?? '')
                  ? null
                  : 'Enter your password.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorMessage(_error!),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy ? const _ButtonProgress() : const Text('Log in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Back to profiles'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthPage extends StatelessWidget {
  const _AuthPage({required this.child, this.title, this.subtitle});

  final Widget child;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(constraints.maxWidth < 420 ? 20 : 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: const BorderSide(color: Color(0xFFE5ECE9)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(
                      constraints.maxWidth < 420 ? 22 : 34,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title == null)
                          child
                        else ...[
                          const _AuthBrand(),
                          const SizedBox(height: 28),
                          Text(
                            title!,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle!,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                          const SizedBox(height: 24),
                          child,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    final text = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'Abacus Master',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          'Small steps. Brilliant minds.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final icon = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFFFCB62),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Icon(Icons.calculate_rounded, size: 27),
    );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [icon, const SizedBox(height: 10), text],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        const SizedBox(width: 12),
        Flexible(child: text),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8E2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF913D31),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _NoticeMessage extends StatelessWidget {
  const _NoticeMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE4F5EF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message),
    ),
  );
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

Widget _usernameField({
  required TextEditingController controller,
  required TextInputAction textInputAction,
  required ValueChanged<String> onSubmitted,
  required FormFieldValidator<String> validator,
}) => TextFormField(
  controller: controller,
  decoration: const InputDecoration(
    labelText: 'Username',
    hintText: 'For example, sam_learner',
    prefixIcon: Icon(Icons.person_outline_rounded),
    border: OutlineInputBorder(),
  ),
  keyboardType: TextInputType.text,
  textCapitalization: TextCapitalization.none,
  textInputAction: textInputAction,
  autocorrect: false,
  enableSuggestions: false,
  autofillHints: const [AutofillHints.username],
  validator: validator,
  onFieldSubmitted: onSubmitted,
);

Widget _passwordField({
  required TextEditingController controller,
  required FocusNode focusNode,
  required bool visible,
  required ValueChanged<bool> onVisibilityChanged,
  required String label,
  required String hint,
  required String autofillHint,
  required TextInputAction textInputAction,
  required ValueChanged<String> onSubmitted,
  required FormFieldValidator<String> validator,
}) => TextFormField(
  controller: controller,
  focusNode: focusNode,
  decoration: InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: const Icon(Icons.lock_outline_rounded),
    suffixIcon: IconButton(
      tooltip: visible ? 'Hide $label' : 'Show $label',
      onPressed: () => onVisibilityChanged(!visible),
      icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
    ),
    border: const OutlineInputBorder(),
  ),
  obscureText: !visible,
  keyboardType: TextInputType.visiblePassword,
  textInputAction: textInputAction,
  autofillHints: [autofillHint],
  validator: validator,
  onFieldSubmitted: onSubmitted,
);
