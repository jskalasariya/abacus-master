import '../domain/profiles/profile_input_rules.dart';
import '../domain/profiles/profile_repository.dart';
import '../domain/profiles/user_profile.dart';

/// Coordinates profile creation and an in-memory authenticated session.
///
/// Credentials are verified by the repository's password-hashing adapter.
/// Session state is cleared before each login attempt and is never persisted.
final class AuthenticationService {
  AuthenticationService(this._profiles);

  final ProfileRepository _profiles;
  UserProfile? _activeProfile;

  bool get isAuthenticated => _activeProfile != null;
  String? get activeUserId => _activeProfile?.id;
  UserProfile? get activeProfile => _activeProfile;

  /// Creates a profile but does not automatically authenticate it.
  Future<UserProfile> createProfile({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = ProfileInputRules.normalizeUsername(username);
    if (normalizedUsername == null) {
      throw const InvalidAuthenticationInputException(
        'Username must be 3-24 ASCII letters, numbers, or underscores.',
      );
    }
    if (!ProfileInputRules.isValidPassword(password)) {
      throw const InvalidAuthenticationInputException(
        'Password must contain between 8 and 128 characters.',
      );
    }
    return _profiles.createProfile(
      username: normalizedUsername,
      password: password,
    );
  }

  /// Logs in with normalized credentials, returning a profile without hashes.
  ///
  /// Invalid usernames and wrong passwords deliberately share one error.
  /// A failed attempt leaves no authenticated session.
  Future<UserProfile> login({
    required String username,
    required String password,
  }) async {
    _activeProfile = null;
    final normalizedUsername = ProfileInputRules.normalizeUsername(username);
    if (normalizedUsername == null ||
        !ProfileInputRules.isValidPassword(password)) {
      throw const LoginFailedException();
    }

    final profile = await _profiles.verifyCredentials(
      username: normalizedUsername,
      password: password,
    );
    if (profile == null) throw const LoginFailedException();

    _activeProfile = profile;
    return profile;
  }

  /// Changes the password for the profile authenticated in this process.
  /// Verification and hashing are delegated to the existing profile adapter.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final profile = _activeProfile;
    if (profile == null) throw const NotAuthenticatedException();
    if (!ProfileInputRules.isValidPassword(newPassword)) {
      throw const InvalidAuthenticationInputException(
        'Password must contain between 8 and 128 characters.',
      );
    }
    await _profiles.changePassword(
      id: profile.id,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  void logout() {
    _activeProfile = null;
  }
}

sealed class AuthenticationException implements Exception {
  const AuthenticationException(this.message);
  final String message;

  @override
  String toString() => message;
}

final class InvalidAuthenticationInputException
    extends AuthenticationException {
  const InvalidAuthenticationInputException(super.message);
}

final class LoginFailedException extends AuthenticationException {
  const LoginFailedException()
    : super('Unable to log in with those credentials.');
}

final class NotAuthenticatedException extends AuthenticationException {
  const NotAuthenticatedException()
    : super('Sign in before changing a profile password.');
}
