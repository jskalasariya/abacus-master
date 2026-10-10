import 'user_profile.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> createProfile({
    required String username,
    required String password,
  });

  Future<UserProfile?> getProfileById(String id);
  Future<UserProfile?> getProfileByUsername(String username);
  Future<List<UserProfile>> getAllProfiles();

  /// Returns a safe profile only when both credentials match; never returns a hash.
  Future<UserProfile?> verifyCredentials({
    required String username,
    required String password,
  });
  Future<UserSettings?> getSettings(String userId);

  Future<UserProfile> updateProfile({
    required String id,
    String? username,
    String? newPassword,
  });

  /// Verifies the current credential and replaces only this profile's hash.
  Future<void> changePassword({
    required String id,
    required String currentPassword,
    required String newPassword,
  });

  Future<UserSettings> updateSettings(UserSettings settings);
  Future<bool> deleteProfile(String id);
}

sealed class ProfileRepositoryException implements Exception {
  const ProfileRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

final class InvalidProfileDataException extends ProfileRepositoryException {
  const InvalidProfileDataException(super.message);
}

final class DuplicateUsernameException extends ProfileRepositoryException {
  const DuplicateUsernameException(super.message);
}

final class ProfileNotFoundException extends ProfileRepositoryException {
  const ProfileNotFoundException(super.message);
}

final class IncorrectCurrentPasswordException
    extends ProfileRepositoryException {
  const IncorrectCurrentPasswordException()
    : super('The current password is incorrect.');
}

final class ProfileStorageException extends ProfileRepositoryException {
  const ProfileStorageException(super.message);
}
