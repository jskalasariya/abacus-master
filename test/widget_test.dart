import 'dart:async';

import 'package:abacus_master/application/authentication_controller.dart';
import 'package:abacus_master/data/database/app_database.dart';
import 'package:abacus_master/data/security/argon2_password_hasher.dart';
import 'package:abacus_master/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first run guides the learner to create a profile', (
    tester,
  ) async {
    final fixture = await _AppFixture.create();
    await _pumpApp(tester, fixture);
    addTearDown(() => _disposeApp(tester));

    expect(find.text('Let’s get started!'), findsOneWidget);
    expect(find.text('Create first profile'), findsOneWidget);
    expect(find.text('Who is practising today?'), findsNothing);
  });

  testWidgets('profile creation continues to login and then the home screen', (
    tester,
  ) async {
    final fixture = await _AppFixture.create();
    await _pumpApp(tester, fixture);
    addTearDown(() => _disposeApp(tester));

    await tester.tap(find.text('Create first profile'));
    await tester.pumpAndSettle();
    await _fillCreateForm(
      tester,
      username: 'New_Learner',
      password: 'a safe passphrase',
      confirmation: 'a safe passphrase',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create profile'));
    await tester.pumpAndSettle();

    expect(
      find.text('Profile created. Sign in to start practising.'),
      findsOneWidget,
    );
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'a safe passphrase',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Practising as new_learner'), findsOneWidget);
    expect(find.text('Start Practising'), findsOneWidget);
  });

  testWidgets('duplicate usernames show a friendly message', (tester) async {
    final fixture = await _AppFixture.create(
      profiles: const [_TestProfile('already_here', 'a safe passphrase')],
    );
    await _pumpApp(tester, fixture);
    addTearDown(() => _disposeApp(tester));

    await tester.tap(find.text('Add a profile'));
    await tester.pumpAndSettle();
    await _fillCreateForm(
      tester,
      username: 'ALREADY_HERE',
      password: 'another passphrase',
      confirmation: 'another passphrase',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create profile'));
    await tester.pumpAndSettle();

    expect(
      find.text('That username is already taken. Try another.'),
      findsOneWidget,
    );
    expect(find.text('Create a profile'), findsOneWidget);
  });

  testWidgets('bad credentials fail generically, valid login reaches home', (
    tester,
  ) async {
    final fixture = await _AppFixture.create(
      profiles: const [_TestProfile('learner_one', 'a safe passphrase')],
    );
    await _pumpApp(tester, fixture);
    addTearDown(() => _disposeApp(tester));

    await tester.tap(find.text('learner_one'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong password');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(
      find.text('We couldn’t sign in with those details.'),
      findsOneWidget,
    );
    expect(find.text('Start Practising'), findsNothing);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'a safe passphrase',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Practising as learner_one'), findsOneWidget);
  });

  testWidgets('logout returns to profile selection', (tester) async {
    final fixture = await _AppFixture.create(
      profiles: const [_TestProfile('learner_one', 'a safe passphrase')],
    );
    await _pumpApp(tester, fixture);
    addTearDown(() => _disposeApp(tester));

    await _signIn(
      tester,
      username: 'learner_one',
      password: 'a safe passphrase',
    );
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Who is practising today?'), findsOneWidget);
    expect(find.text('learner_one'), findsOneWidget);
  });

  testWidgets('switching profiles requires the second account password', (
    tester,
  ) async {
    final fixture = await _AppFixture.create(
      profiles: const [
        _TestProfile('first_learner', 'first passphrase'),
        _TestProfile('second_learner', 'second passphrase'),
      ],
    );
    await _pumpApp(tester, fixture);
    addTearDown(() => _disposeApp(tester));

    await _signIn(
      tester,
      username: 'first_learner',
      password: 'first passphrase',
    );
    await tester.tap(find.text('Switch profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second_learner'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'first passphrase',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(
      find.text('We couldn’t sign in with those details.'),
      findsOneWidget,
    );
    expect(find.text('Practising as first_learner'), findsNothing);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'second passphrase',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Practising as second_learner'), findsOneWidget);
  });

  testWidgets('form validation and a busy state prevent duplicate submits', (
    tester,
  ) async {
    final fixture = await _AppFixture.create();
    await _pumpApp(tester, fixture);
    addTearDown(() => _disposeApp(tester));
    await tester.tap(find.text('Create first profile'));
    await tester.pumpAndSettle();

    await _fillCreateForm(
      tester,
      username: 'new_learner',
      password: 'a safe passphrase',
      confirmation: 'does not match',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create profile'));
    await tester.pumpAndSettle();
    expect(find.text('The passwords don’t match.'), findsOneWidget);
    expect(fixture.hasher.hashCalls, 0);

    await tester.enterText(
      find.byType(TextFormField).at(2),
      'a safe passphrase',
    );
    fixture.hasher.hashGate = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, 'Create profile'));
    await tester.pump();

    final submitButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submitButton.onPressed, isNull);
    expect(fixture.hasher.hashCalls, 1);
    fixture.hasher.hashGate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Profile created. Sign in to start practising.'),
      findsOneWidget,
    );
  });

  testWidgets('database startup failure has a retry path', (tester) async {
    final fixture = await _AppFixture.create();
    var factoryCalls = 0;
    await tester.pumpWidget(
      AbacusMasterApp(
        controllerFactory: () async {
          factoryCalls++;
          if (factoryCalls == 1) throw StateError('local storage unavailable');
          return fixture.controller;
        },
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => _disposeApp(tester));

    expect(
      find.text('We couldn’t open local profiles. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Create first profile'), findsOneWidget);
    expect(factoryCalls, 2);
  });

  testWidgets('home screen remains responsive on a narrow phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = await _AppFixture.create(
      profiles: const [_TestProfile('small_screen', 'a safe passphrase')],
    );
    await _pumpApp(tester, fixture);
    addTearDown(() => _disposeApp(tester));
    await _signIn(
      tester,
      username: 'small_screen',
      password: 'a safe passphrase',
    );

    expect(find.text('Practising as small_screen'), findsOneWidget);
    expect(find.text('Start Practising'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpApp(WidgetTester tester, _AppFixture fixture) async {
  await tester.pumpWidget(
    AbacusMasterApp(controllerFactory: () async => fixture.controller),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> _fillCreateForm(
  WidgetTester tester, {
  required String username,
  required String password,
  required String confirmation,
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), username);
  await tester.enterText(find.byType(TextFormField).at(1), password);
  await tester.enterText(find.byType(TextFormField).at(2), confirmation);
}

Future<void> _signIn(
  WidgetTester tester, {
  required String username,
  required String password,
}) async {
  await tester.tap(find.text(username));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).at(1), password);
  await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
  await tester.pumpAndSettle();
}

final class _TestProfile {
  const _TestProfile(this.username, this.password);
  final String username;
  final String password;
}

final class _AppFixture {
  _AppFixture(this.database, this.controller, this.hasher);

  final AppDatabase database;
  final AuthenticationController controller;
  final _TestPasswordHasher hasher;

  static Future<_AppFixture> create({
    List<_TestProfile> profiles = const [],
  }) async {
    final database = AppDatabase.inMemory();
    final hasher = _TestPasswordHasher();
    final controller = AuthenticationController.forDatabase(
      database,
      passwordHasher: hasher,
    );
    for (final profile in profiles) {
      await controller.createProfile(
        username: profile.username,
        password: profile.password,
      );
    }
    return _AppFixture(database, controller, hasher);
  }
}

final class _TestPasswordHasher implements PasswordHasher {
  Completer<void>? hashGate;
  int hashCalls = 0;

  @override
  Future<String> hash(String password) async {
    hashCalls++;
    final gate = hashGate;
    if (gate != null) await gate.future;
    return 'widget-test-hash-$password';
  }

  @override
  Future<bool> verify(String password, String encodedHash) async =>
      encodedHash == await hash(password);
}
