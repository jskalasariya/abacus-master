/// Input rules shared by profile creation and authentication.
abstract final class ProfileInputRules {
  static final _usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');

  static String? normalizeUsername(String username) {
    final normalized = username.trim().toLowerCase();
    return _usernamePattern.hasMatch(normalized) ? normalized : null;
  }

  static bool isValidPassword(String password) =>
      password.length >= 8 && password.length <= 128;
}
