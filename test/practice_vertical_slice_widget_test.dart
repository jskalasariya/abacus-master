import 'dart:async';

import 'package:abacus_master/application/practice_session_coordinator.dart';
import 'package:abacus_master/application/authentication_controller.dart';
import 'package:abacus_master/application/authentication_service.dart';
import 'package:abacus_master/data/database/app_database.dart';
import 'package:abacus_master/data/security/argon2_password_hasher.dart';
import 'package:abacus_master/domain/answer_feedback_mode.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_operation.dart';
import 'package:abacus_master/domain/sessions/session_configuration.dart';
import 'package:abacus_master/main.dart';
import 'package:abacus_master/presentation/practice_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'profile preference becomes the config default and a test override stays local',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.database.close();
      });
      await _openSignedInHome(tester, fixture);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await _scrollUntilBuilt(tester, find.text('At the end of the test'));
      await tester.tap(
        find.widgetWithText(ChoiceChip, 'At the end of the test'),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Save practice settings'));
      await tester.tap(find.text('Save practice settings'));
      await tester.pumpAndSettle();
      expect(
        (await fixture.controller.loadActiveSettings())!.answerFeedbackMode,
        AnswerFeedbackMode.endOfTest,
      );

      await _openPractice(tester);
      await tester.enterText(find.byType(TextFormField).at(0), '1');
      await _scrollUntilBuilt(tester, find.text('At the end of the test'));
      final endChoice = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'At the end of the test'),
      );
      expect(endChoice.selected, isTrue);
      await tester.tap(find.widgetWithText(ChoiceChip, 'After each answer'));
      await tester.pump();
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'After each answer'),
            )
            .selected,
        isTrue,
      );
      await _startConfiguredSession(tester);
      await _pumpUntil(tester, find.text('Question 1'));
      await tester.tap(
        find
            .descendant(
              of: find.byType(GridView).last,
              matching: find.byType(FilledButton),
            )
            .last,
      );
      await _pumpUntil(tester, find.text('Question review'));
      await tester.pump(const Duration(milliseconds: 400));

      final completed = await fixture.controller.practiceSessions
          .listCompletedSessions(fixture.controller.activeUserId!);
      expect(
        completed.single.configuration.answerFeedbackMode,
        AnswerFeedbackMode.immediate,
      );
      expect(
        (await fixture.controller.loadActiveSettings())!.answerFeedbackMode,
        AnswerFeedbackMode.endOfTest,
      );
    },
  );

  testWidgets('end-of-test mode hides answer correctness during the session', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.database.close();
    });
    await _openSignedInHome(tester, fixture);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await _scrollUntilBuilt(tester, find.text('At the end of the test'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'At the end of the test'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save practice settings'));
    await tester.tap(find.text('Save practice settings'));
    await tester.pumpAndSettle();

    await _openPractice(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '2');
    await _scrollUntilBuilt(tester, find.text('At the end of the test'));
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, 'At the end of the test'),
          )
          .selected,
      isTrue,
    );
    await _startConfiguredSession(tester);
    await _pumpUntil(tester, find.text('Question 1'));
    await tester.tap(find.byType(FilledButton).last);
    await _pumpUntil(tester, find.text('Question 2'));

    expect(find.text('Question 2'), findsOneWidget);
    expect(find.text('Answer saved!'), findsNothing);
    expect(find.textContaining('That'), findsNothing);
    expect(find.text('Good try! Keep going.'), findsNothing);
    expect(find.textContaining('The answer was'), findsNothing);
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('saved difficulty and decimal precision seed practice options', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.database.close();
    });
    await _openSignedInHome(tester, fixture);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Advanced'));
    await tester.tap(find.widgetWithText(ChoiceChip, '3 decimal places'));
    await _scrollUntilBuilt(tester, find.text('Save practice settings'));
    await tester.tap(find.text('Save practice settings'));
    await tester.pumpAndSettle();

    final saved = await fixture.controller.loadActiveSettings();
    expect(saved!.difficulty, ArithmeticDifficulty.advanced);
    expect(saved.decimalPrecision, 3);

    await _openPractice(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Advanced'))
          .selected,
      isTrue,
    );
    await _scrollUntilBuilt(tester, find.text('Include decimal questions'));
    final decimalSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Include decimal questions'),
    );
    expect(decimalSwitch.value, isTrue);
    await _scrollUntilBuilt(tester, find.text('3 places'));
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '3 places'))
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'password change validates credentials and accepts the new password',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.database.close();
      });
      await _openSignedInHome(tester, fixture);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await _fillPasswordChange(
        tester,
        current: 'safe passphrase',
        next: 'replacement passphrase',
        confirmation: 'different passphrase',
      );
      await _submitPasswordChange(tester);
      await tester.pumpAndSettle();
      expect(find.text('The new passwords do not match.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), 'short');
      await tester.enterText(find.byType(TextFormField).at(2), 'short');
      await _submitPasswordChange(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Use 8 to 128 characters for your password.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'replacement passphrase',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'replacement passphrase',
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'wrong current password',
      );
      await _submitPasswordChange(tester);
      await tester.pumpAndSettle();
      expect(find.text('The current password is incorrect.'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'safe passphrase',
      );
      await _submitPasswordChange(tester);
      expect(find.text('Your password has been changed.'), findsOneWidget);
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .every((field) => field.controller!.text.isEmpty),
        isTrue,
      );

      fixture.controller.logout();
      await expectLater(
        fixture.controller.login(
          username: 'slice_learner',
          password: 'safe passphrase',
        ),
        throwsA(isA<LoginFailedException>()),
      );
      await fixture.controller.login(
        username: 'slice_learner',
        password: 'replacement passphrase',
      );
    },
  );

  testWidgets('password storage failure never shows success', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.database.close();
    });
    await _openSignedInHome(tester, fixture);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await fixture.database.customStatement('''
      CREATE TRIGGER fail_settings_screen_password_change
      BEFORE UPDATE OF password_hash ON user_profiles
      BEGIN SELECT RAISE(ABORT, 'forced test failure'); END
    ''');

    await _fillPasswordChange(
      tester,
      current: 'safe passphrase',
      next: 'replacement passphrase',
      confirmation: 'replacement passphrase',
    );
    await _submitPasswordChange(tester);

    expect(
      find.text(
        'We could not update your password. No changes were saved. Please try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Your password has been changed.'), findsNothing);
    fixture.controller.logout();
    await fixture.controller.login(
      username: 'slice_learner',
      password: 'safe passphrase',
    );
  });

  testWidgets('immediate feedback delays briefly then advances automatically', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.database.close();
    });
    await fixture.controller.login(
      username: 'slice_learner',
      password: 'safe passphrase',
    );
    final coordinator = PracticeSessionCoordinator(
      configuration: SessionConfiguration(
        questionCount: 2,
        duration: const Duration(minutes: 1),
        operations: const {ArithmeticOperation.addition},
        decimalProbability: 0,
      ),
      authenticatedUserId: () => fixture.controller.activeUserId,
      repository: fixture.controller.practiceSessions,
      seed: 17,
    );
    await coordinator.start();
    final releaseDelay = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: LivePracticeScreen(
          coordinator: coordinator,
          wait: (_) => releaseDelay.future,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Question 1'));

    await tester.tap(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(FilledButton),
          )
          .first,
    );
    await _pumpUntil(tester, find.text('Next question coming up…'));
    expect(find.text('Next question coming up…'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Next question coming up…'), findsOneWidget);
    releaseDelay.complete();
    await tester.pump();
    await _pumpUntil(tester, find.text('Question 2'));
    expect(find.text('Question 2'), findsOneWidget);
  });

  testWidgets('failed answer write keeps the same question available', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.database.close();
    });
    await _openSignedInHome(tester, fixture);
    await _openPractice(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '2');
    await _startConfiguredSession(tester);
    await _pumpUntil(tester, find.text('Question 1'));
    await fixture.database.customStatement('''
      CREATE TRIGGER fail_widget_attempt BEFORE INSERT ON practice_question_attempts
      BEGIN SELECT RAISE(ABORT, 'injected widget write failure'); END
    ''');

    final answer = find
        .descendant(
          of: find.byType(GridView),
          matching: find.byType(FilledButton),
        )
        .first;
    await tester.tap(answer);
    await _pumpUntil(
      tester,
      find.textContaining('Your question is still here'),
    );
    expect(find.text('Question 1'), findsOneWidget);
    expect(find.textContaining('Your question is still here'), findsOneWidget);
    expect(
      (await fixture.controller.practiceSessions.listCompletedSessions(
        fixture.controller.activeUserId!,
      )),
      isEmpty,
    );

    await fixture.database.customStatement('DROP TRIGGER fail_widget_attempt');
    await tester.tap(answer);
    await _pumpUntil(tester, find.text('Question 2'));
    expect(find.text('Question 2'), findsOneWidget);
  });

  testWidgets(
    'authenticated learner configures, answers and reviews a session',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.database.close();
      });
      await tester.pumpWidget(
        AbacusMasterApp(controllerFactory: () async => fixture.controller),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('slice_learner'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'safe passphrase',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Practice'));
      await tester.tap(find.text('Practice'));
      await tester.pumpAndSettle();

      expect(find.text('Difficulty'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), '1');
      await _scrollUntilBuilt(tester, find.text('After each answer'));
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'After each answer'),
            )
            .selected,
        isTrue,
      );
      await _scrollUntilBuilt(tester, find.text('Start practising'));
      expect(find.text('Start practising'), findsOneWidget);
      await _startConfiguredSession(tester);
      await _pumpUntil(tester, find.text('Question 1'));

      expect(find.text('Question 1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GridView).last,
          matching: find.byType(FilledButton),
        ),
        findsNWidgets(4),
      );
      await tester.tap(find.byType(FilledButton).last);
      await _pumpUntil(tester, find.text('Question review'));

      expect(find.text('Question review'), findsOneWidget);
      expect(find.text('Attempted'), findsOneWidget);
      expect(fixture.controller.practiceSessions, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'practice configuration and question choices fit a narrow screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      final fixture = await _Fixture.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.database.close();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        AbacusMasterApp(controllerFactory: () async => fixture.controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('slice_learner'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'safe passphrase',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Practice'));
      await tester.tap(find.text('Practice'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextFormField).at(0), '1');
      await _scrollUntilBuilt(tester, find.text('Start practising'));
      expect(find.text('Start practising'), findsOneWidget);
      await _startConfiguredSession(tester);
      await _pumpUntil(tester, find.text('Question 1'));
      expect(
        find.descendant(
          of: find.byType(GridView).last,
          matching: find.byType(FilledButton),
        ),
        findsNWidgets(4),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _openSignedInHome(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(
    AbacusMasterApp(controllerFactory: () async => fixture.controller),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('slice_learner'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).at(1), 'safe passphrase');
  await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
  await tester.pumpAndSettle();
}

Future<void> _openPractice(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Practice'));
  await tester.tap(find.text('Practice'));
  await tester.pumpAndSettle();
}

Future<void> _fillPasswordChange(
  WidgetTester tester, {
  required String current,
  required String next,
  required String confirmation,
}) async {
  await _scrollUntilBuilt(tester, find.text('Current password'));
  await tester.enterText(find.byType(TextFormField).at(0), current);
  await tester.enterText(find.byType(TextFormField).at(1), next);
  await tester.enterText(find.byType(TextFormField).at(2), confirmation);
}

Future<void> _submitPasswordChange(WidgetTester tester) async {
  final button = find.widgetWithText(OutlinedButton, 'Change password');
  await _scrollUntilBuilt(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _startConfiguredSession(WidgetTester tester) async {
  await _scrollUntilBuilt(tester, find.text('Start practising'));
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  final configList = find.byType(ListView).last;
  await tester.drag(configList, const Offset(0, -220));
  await tester.pump();
  final startButton = find.widgetWithText(FilledButton, 'Start practising');
  await tester.ensureVisible(startButton);
  await tester.tap(startButton);
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scrollUntilBuilt(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 8 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pump();
  }
}

final class _Fixture {
  _Fixture(this.database, this.controller);

  final AppDatabase database;
  final AuthenticationController controller;

  static Future<_Fixture> create() async {
    final database = AppDatabase.inMemory();
    final hasher = _Hasher();
    final controller = AuthenticationController.forDatabase(
      database,
      passwordHasher: hasher,
    );
    await controller.createProfile(
      username: 'slice_learner',
      password: 'safe passphrase',
    );
    return _Fixture(database, controller);
  }
}

final class _Hasher implements PasswordHasher {
  @override
  Future<String> hash(String password) async => 'test-hash:$password';

  @override
  Future<bool> verify(String password, String encodedHash) async =>
      encodedHash == 'test-hash:$password';
}
