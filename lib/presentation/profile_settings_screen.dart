import 'package:flutter/material.dart';

import '../application/authentication_service.dart';
import '../domain/answer_feedback_mode.dart';
import '../domain/arithmetic/arithmetic_operation.dart';
import '../domain/profiles/profile_input_rules.dart';
import '../domain/profiles/profile_repository.dart';
import '../domain/profiles/user_profile.dart';

typedef SaveProfileSettings = Future<UserSettings> Function(
  UserSettings settings,
);
typedef ChangeProfilePassword = Future<void> Function({
  required String currentPassword,
  required String newPassword,
});

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({
    required this.initialSettings,
    required this.onSave,
    required this.onChangePassword,
    super.key,
  });

  final UserSettings initialSettings;
  final SaveProfileSettings onSave;
  final ChangeProfilePassword onChangePassword;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _passwordFormKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  late AnswerFeedbackMode _feedbackMode;
  late ArithmeticDifficulty _difficulty;
  late int _decimalPrecision;
  bool _savingSettings = false;
  bool _changingPassword = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmation = false;
  String? _settingsError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _feedbackMode = widget.initialSettings.answerFeedbackMode;
    _difficulty = widget.initialSettings.difficulty;
    _decimalPrecision = widget.initialSettings.decimalPrecision;
  }

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_savingSettings) return;
    setState(() {
      _savingSettings = true;
      _settingsError = null;
    });
    try {
      await widget.onSave(
        widget.initialSettings.copyWith(
          difficulty: _difficulty,
          decimalPrecision: _decimalPrecision,
          answerFeedbackMode: _feedbackMode,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your practice settings are saved.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingSettings = false;
        _settingsError = 'We could not save these settings. Please try again.';
      });
    }
  }

  Future<void> _changePassword() async {
    if (_changingPassword || !_passwordFormKey.currentState!.validate()) return;
    setState(() {
      _changingPassword = true;
      _passwordError = null;
    });
    try {
      await widget.onChangePassword(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      setState(() => _changingPassword = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your password has been changed.')),
      );
    } on IncorrectCurrentPasswordException {
      _setPasswordError('The current password is incorrect.');
    } on InvalidAuthenticationInputException catch (error) {
      _setPasswordError(error.message);
    } on InvalidProfileDataException catch (error) {
      _setPasswordError(error.message);
    } on ProfileStorageException {
      _setPasswordError(
        'We could not update your password. No changes were saved. Please try again.',
      );
    } catch (_) {
      _setPasswordError('We could not update your password. Please try again.');
    }
  }

  void _setPasswordError(String message) {
    if (!mounted) return;
    setState(() {
      _changingPassword = false;
      _passwordError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Make practice feel right for you.',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF183538),
                  ),
                ),
                const SizedBox(height: 22),
                _settingsCard(
                  context,
                  title: 'Difficulty',
                  description: 'Choose the level you want to start with.',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ArithmeticDifficulty.values.map((difficulty) {
                      return ChoiceChip(
                        label: Text(_difficultyName(difficulty)),
                        selected: _difficulty == difficulty,
                        onSelected: _savingSettings || _changingPassword
                            ? null
                            : (_) => setState(() => _difficulty = difficulty),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
                _settingsCard(
                  context,
                  title: 'Decimal precision',
                  description: 'Zero keeps practice to whole numbers. Choose 1, 2, or 3 decimal places to include decimals by default.',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [0, 1, 2, 3].map((precision) {
                      return ChoiceChip(
                        label: Text(_precisionName(precision)),
                        selected: _decimalPrecision == precision,
                        onSelected: _savingSettings || _changingPassword
                            ? null
                            : (_) =>
                                  setState(() => _decimalPrecision = precision),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
                _settingsCard(
                  context,
                  title: 'Answer feedback',
                  description: 'Choose when you want to see your answers.',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _feedbackChoice(
                        AnswerFeedbackMode.immediate,
                        'After each answer',
                      ),
                      _feedbackChoice(
                        AnswerFeedbackMode.endOfTest,
                        'At the end of the test',
                      ),
                    ],
                  ),
                ),
                if (_settingsError != null) ...[
                  const SizedBox(height: 12),
                  _inlineError(_settingsError!),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _savingSettings || _changingPassword
                      ? null
                      : _saveSettings,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: const Color(0xFF168777),
                  ),
                  child: Text(
                    _savingSettings ? 'Saving…' : 'Save practice settings',
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Change password',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF183538),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use your current password to set a new one for this profile.',
                ),
                const SizedBox(height: 12),
                Form(
                  key: _passwordFormKey,
                  child: Column(
                    children: [
                      _passwordField(
                        controller: _currentPassword,
                        label: 'Current password',
                        visible: _showCurrentPassword,
                        toggleVisibility: () => setState(
                          () => _showCurrentPassword = !_showCurrentPassword,
                        ),
                        action: TextInputAction.next,
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your current password.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _passwordField(
                        controller: _newPassword,
                        label: 'New password',
                        visible: _showNewPassword,
                        toggleVisibility: () => setState(
                          () => _showNewPassword = !_showNewPassword,
                        ),
                        action: TextInputAction.next,
                        validator: (value) =>
                            value == null ||
                                !ProfileInputRules.isValidPassword(value)
                            ? 'Use 8 to 128 characters for your password.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _passwordField(
                        controller: _confirmPassword,
                        label: 'Confirm new password',
                        visible: _showConfirmation,
                        toggleVisibility: () => setState(
                          () => _showConfirmation = !_showConfirmation,
                        ),
                        action: TextInputAction.done,
                        validator: (value) => value != _newPassword.text
                            ? 'The new passwords do not match.'
                            : null,
                      ),
                    ],
                  ),
                ),
                if (_passwordError != null) ...[
                  const SizedBox(height: 12),
                  _inlineError(_passwordError!),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _changingPassword || _savingSettings
                      ? null
                      : _changePassword,
                  icon: _changingPassword
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_reset_rounded),
                  label: Text(
                    _changingPassword
                        ? 'Changing password…'
                        : 'Change password',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsCard(
    BuildContext context, {
    required String title,
    required String description,
    required Widget child,
  }) => Card(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(description),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback toggleVisibility,
    required TextInputAction action,
    required FormFieldValidator<String> validator,
  }) => TextFormField(
    controller: controller,
    obscureText: !visible,
    keyboardType: TextInputType.visiblePassword,
    textInputAction: action,
    enabled: !_changingPassword,
    autocorrect: false,
    enableSuggestions: false,
    validator: validator,
    onChanged: (_) {
      if (_passwordError != null) setState(() => _passwordError = null);
    },
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: visible ? 'Hide $label' : 'Show $label',
        onPressed: _changingPassword ? null : toggleVisibility,
        icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
      ),
    ),
  );

  Widget _inlineError(String message) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Widget _feedbackChoice(AnswerFeedbackMode mode, String label) => ChoiceChip(
    label: Text(label),
    selected: _feedbackMode == mode,
    onSelected: _savingSettings || _changingPassword
        ? null
        : (_) => setState(() => _feedbackMode = mode),
  );

  static String _difficultyName(ArithmeticDifficulty difficulty) =>
      switch (difficulty) {
        ArithmeticDifficulty.beginner => 'Beginner',
        ArithmeticDifficulty.medium => 'Medium',
        ArithmeticDifficulty.advanced => 'Advanced',
      };

  static String _precisionName(int precision) => switch (precision) {
    0 => 'Whole numbers only',
    1 => '1 decimal place',
    2 => '2 decimal places',
    3 => '3 decimal places',
    _ => throw ArgumentError.value(precision, 'precision'),
  };
}
