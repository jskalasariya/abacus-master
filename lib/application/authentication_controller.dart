import 'package:flutter/foundation.dart';

import '../data/database/app_database.dart';
import '../data/profiles/sqlite_profile_repository.dart';
import '../data/security/argon2_password_hasher.dart';
import '../domain/profiles/profile_repository.dart';
import '../domain/profiles/user_profile.dart';
import '../data/sessions/sqlite_practice_session_repository.dart';
import '../domain/sessions/practice_session.dart';
import '../domain/sessions/practice_session_repository.dart';
import 'authentication_service.dart';

typedef AuthenticationControllerFactory =
    Future<AuthenticationController> Function();

/// Coordinates app startup and profile/authentication operations for the UI.
///
/// Widgets call this controller instead of opening SQLite or querying Drift.
final class AuthenticationController extends ChangeNotifier {
  AuthenticationController._(this._database, this._profiles)
    : authentication = AuthenticationService(_profiles),
      practiceSessions = SqlitePracticeSessionRepository(_database);

  factory AuthenticationController.forDatabase(
    AppDatabase database, {
    PasswordHasher? passwordHasher,
  }) => AuthenticationController._(
    database,
    SqliteProfileRepository(database, passwordHasher: passwordHasher),
  );

  static Future<AuthenticationController> open() async {
    final database = AppDatabase.open();
    final controller = AuthenticationController.forDatabase(database);
    try {
      await controller.loadProfiles();
      return controller;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  final AppDatabase _database;
  final ProfileRepository _profiles;
  final AuthenticationService authentication;
  final PracticeSessionRepository practiceSessions;

  UserProfile? get activeProfile => authentication.activeProfile;
  String? get activeUserId => authentication.activeUserId;
  bool get isAuthenticated => authentication.isAuthenticated;

  Future<List<UserProfile>> loadProfiles() => _profiles.getAllProfiles();

  Future<UserSettings?> loadActiveSettings() {
    final userId = activeUserId;
    if (userId == null) {
      throw StateError('Sign in before opening profile settings.');
    }
    return _profiles.getSettings(userId);
  }

  Future<UserSettings> saveActiveSettings(UserSettings settings) async {
    if (activeUserId != settings.userId) {
      throw StateError(
        'Profile settings can only be saved for the signed-in user.',
      );
    }
    return _profiles.updateSettings(settings);
  }

  Future<void> changeActivePassword({
    required String currentPassword,
    required String newPassword,
  }) => authentication.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  Future<List<PersistedPracticeSession>> recoverInterruptedSessions() =>
      practiceSessions.recoverUnfinishedSessions();

  Future<UserProfile> createProfile({
    required String username,
    required String password,
  }) => authentication.createProfile(username: username, password: password);

  Future<UserProfile> login({
    required String username,
    required String password,
  }) async {
    try {
      return await authentication.login(username: username, password: password);
    } finally {
      notifyListeners();
    }
  }

  void logout() {
    authentication.logout();
    notifyListeners();
  }

  Future<void> close() async {
    await _database.close();
    dispose();
  }
}
