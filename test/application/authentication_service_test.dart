import 'package:abacus_master/application/authentication_service.dart';
import 'package:abacus_master/data/database/app_database.dart';
import 'package:abacus_master/data/profiles/sqlite_profile_repository.dart';
import 'package:abacus_master/data/security/argon2_password_hasher.dart';
import 'package:abacus_master/domain/profiles/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Argon2PasswordHasher', () {
    final hasher = Argon2PasswordHasher();

    test('hashes with unique salt and verifies the correct password', () async {
      const password = 'a secure passphrase';
      final firstHash = await hasher.hash(password);
      final secondHash = await hasher.hash(password);

      expect(firstHash, isNot(password));
      expect(secondHash, isNot(firstHash));
      expect(await hasher.verify(password, firstHash), isTrue);
      expect(await hasher.verify('a different passphrase', firstHash), isFalse);
    });

    test('rejects malformed and unsupported encodings safely', () async {
      final malformed = [
        '',
        'argon2id',
        r'argon2id$v=18$m=19456,t=2,p=1$salt$hash',
        r'argon2id$v=19$m=2048,t=1,p=1$salt$hash',
        r'argon2id$v=19$m=19456,t=2,p=1$%%%$%%% ',
        List.filled(129, 'x').join(),
      ];

      for (final encoding in malformed) {
        expect(await hasher.verify('a secure passphrase', encoding), isFalse);
      }
    });
  });

  group('AuthenticationService', () {
    late AppDatabase database;
    late AuthenticationService authentication;

    setUp(() {
      database = AppDatabase.inMemory();
      final hasher = _TestPasswordHasher();
      final profiles = SqliteProfileRepository(
        database,
        passwordHasher: hasher,
        clock: () => DateTime.utc(2026, 4, 5),
      );
      authentication = AuthenticationService(profiles);
    });

    tearDown(() async {
      await database.close();
    });

    test('creates profiles without automatically logging them in', () async {
      final profile = await authentication.createProfile(
        username: '  New_Player ',
        password: 'secure passphrase',
      );

      expect(profile.username, 'new_player');
      expect(authentication.isAuthenticated, isFalse);
      expect(authentication.activeUserId, isNull);
      expect(authentication.activeProfile, isNull);
    });

    test(
      'logs in with a normalized username and exposes only the profile',
      () async {
        final created = await authentication.createProfile(
          username: 'Player_One',
          password: 'secure passphrase',
        );

        final loggedIn = await authentication.login(
          username: ' PLAYER_ONE ',
          password: 'secure passphrase',
        );

        expect(loggedIn, created);
        expect(authentication.isAuthenticated, isTrue);
        expect(authentication.activeUserId, created.id);
        expect(authentication.activeProfile, created);
      },
    );

    test('preserves duplicate username errors from the repository', () async {
      await authentication.createProfile(
        username: 'same_name',
        password: 'secure passphrase',
      );

      await expectLater(
        authentication.createProfile(
          username: ' SAME_NAME ',
          password: 'another passphrase',
        ),
        throwsA(isA<DuplicateUsernameException>()),
      );
      expect(authentication.isAuthenticated, isFalse);
    });

    test('rejects invalid profile-creation credentials', () async {
      for (final username in ['', 'ab', 'has spaces']) {
        await expectLater(
          authentication.createProfile(
            username: username,
            password: 'secure passphrase',
          ),
          throwsA(isA<InvalidAuthenticationInputException>()),
        );
      }
      await expectLater(
        authentication.createProfile(username: 'valid_name', password: ''),
        throwsA(isA<InvalidAuthenticationInputException>()),
      );
    });

    test(
      'uses the same generic failure for invalid usernames and passwords',
      () async {
        await authentication.createProfile(
          username: 'existing_user',
          password: 'secure passphrase',
        );

        final invalidUsername = await _captureLoginFailure(
          authentication,
          username: 'not valid',
          password: 'secure passphrase',
        );
        final wrongPassword = await _captureLoginFailure(
          authentication,
          username: 'existing_user',
          password: 'incorrect password',
        );
        final unknownUsername = await _captureLoginFailure(
          authentication,
          username: 'unknown_user',
          password: 'secure passphrase',
        );
        final emptyPassword = await _captureLoginFailure(
          authentication,
          username: 'existing_user',
          password: '',
        );

        expect(invalidUsername.message, wrongPassword.message);
        expect(unknownUsername.message, wrongPassword.message);
        expect(emptyPassword.message, wrongPassword.message);
        expect(authentication.isAuthenticated, isFalse);
      },
    );

    test('failed login clears any previous session', () async {
      final profile = await authentication.createProfile(
        username: 'session_user',
        password: 'secure passphrase',
      );
      await authentication.login(
        username: 'session_user',
        password: 'secure passphrase',
      );
      expect(authentication.activeUserId, profile.id);

      await expectLater(
        authentication.login(
          username: 'session_user',
          password: 'wrong passphrase',
        ),
        throwsA(isA<LoginFailedException>()),
      );

      expect(authentication.isAuthenticated, isFalse);
      expect(authentication.activeUserId, isNull);
      expect(authentication.activeProfile, isNull);
    });

    test('logout clears the in-memory session', () async {
      await authentication.createProfile(
        username: 'logout_user',
        password: 'secure passphrase',
      );
      await authentication.login(
        username: 'logout_user',
        password: 'secure passphrase',
      );

      authentication.logout();

      expect(authentication.isAuthenticated, isFalse);
      expect(authentication.activeUserId, isNull);
      expect(authentication.activeProfile, isNull);
    });

    test('changes password only for the authenticated profile', () async {
      final first = await authentication.createProfile(
        username: 'password_first',
        password: 'first passphrase',
      );
      final second = await authentication.createProfile(
        username: 'password_second',
        password: 'second passphrase',
      );
      await authentication.login(
        username: first.username,
        password: 'first passphrase',
      );

      await authentication.changePassword(
        currentPassword: 'first passphrase',
        newPassword: 'replacement passphrase',
      );
      expect(authentication.activeProfile, first);

      authentication.logout();
      await expectLater(
        authentication.login(
          username: first.username,
          password: 'first passphrase',
        ),
        throwsA(isA<LoginFailedException>()),
      );
      expect(
        await authentication.login(
          username: first.username,
          password: 'replacement passphrase',
        ),
        first,
      );
      authentication.logout();
      expect(
        await authentication.login(
          username: second.username,
          password: 'second passphrase',
        ),
        second,
      );
    });

    test(
      'password change requires an active profile and valid new password',
      () async {
        await expectLater(
          authentication.changePassword(
            currentPassword: 'old passphrase',
            newPassword: 'new passphrase',
          ),
          throwsA(isA<NotAuthenticatedException>()),
        );

        await authentication.createProfile(
          username: 'password_invalid',
          password: 'old passphrase',
        );
        await authentication.login(
          username: 'password_invalid',
          password: 'old passphrase',
        );
        await expectLater(
          authentication.changePassword(
            currentPassword: 'old passphrase',
            newPassword: 'short',
          ),
          throwsA(isA<InvalidAuthenticationInputException>()),
        );
      },
    );

    test(
      'keeps two profiles independent and requires explicit login',
      () async {
        final first = await authentication.createProfile(
          username: 'first_user',
          password: 'first secure passphrase',
        );
        final second = await authentication.createProfile(
          username: 'second_user',
          password: 'second secure passphrase',
        );
        expect(first.id, isNot(second.id));
        expect(authentication.isAuthenticated, isFalse);

        await authentication.login(
          username: 'first_user',
          password: 'first secure passphrase',
        );
        expect(authentication.activeUserId, first.id);

        authentication.logout();
        await authentication.login(
          username: 'second_user',
          password: 'second secure passphrase',
        );
        expect(authentication.activeUserId, second.id);
        expect(authentication.activeProfile, second);
      },
    );
  });
}

Future<LoginFailedException> _captureLoginFailure(
  AuthenticationService authentication, {
  required String username,
  required String password,
}) async {
  try {
    await authentication.login(username: username, password: password);
  } on LoginFailedException catch (error) {
    return error;
  }
  throw StateError('Expected a generic login failure.');
}

final class _TestPasswordHasher implements PasswordHasher {
  @override
  Future<String> hash(String password) async => 'test-only-hash-$password';

  @override
  Future<bool> verify(String password, String encodedHash) async =>
      encodedHash == await hash(password);
}
