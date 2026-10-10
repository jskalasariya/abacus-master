import 'package:abacus_master/data/database/app_database.dart';
import 'package:abacus_master/data/profiles/sqlite_profile_repository.dart';
import 'package:abacus_master/data/security/argon2_password_hasher.dart';
import 'package:abacus_master/data/sessions/sqlite_practice_session_repository.dart';
import 'package:abacus_master/domain/arithmetic/arithmetic_operation.dart';
import 'package:abacus_master/domain/arithmetic/rational.dart';
import 'package:abacus_master/domain/sessions/practice_session.dart';
import 'package:abacus_master/domain/sessions/session_configuration.dart';
import 'package:abacus_master/domain/sessions/session_models.dart';
import 'package:abacus_master/presentation/practice_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late SqlitePracticeSessionRepository sessions;
  late String userId;

  setUp(() async {
    database = AppDatabase.inMemory();
    final profiles = SqliteProfileRepository(
      database,
      passwordHasher: _TestPasswordHasher(),
    );
    userId = (await profiles.createProfile(
      username: 'history_learner',
      password: 'safe test password',
    )).id;
    sessions = SqlitePracticeSessionRepository(database);
  });

  tearDown(() => database.close());

  testWidgets('empty history and statistics show useful zero-data states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(PracticeHistoryScreen(repository: sessions, userId: userId)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your first result will show up here'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _app(PracticeStatisticsScreen(repository: sessions, userId: userId)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Completed tests'), findsOneWidget);
    expect(find.text('Questions answered'), findsOneWidget);
    expect(find.text('0%'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.text('Finish a test to see your progress here.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Finish a test to see your progress here.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history remains readable on a narrow screen and opens saved review',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final startedAt = DateTime.utc(2026, 1, 1, 10);
      final session = await sessions.createSession(
        userId: userId,
        configuration: SessionConfiguration(
          questionCount: 1,
          operations: const {ArithmeticOperation.addition},
          decimalProbability: 0,
        ),
        startedAt: startedAt,
      );
      await sessions.saveAttempt(
        sessionId: session.id,
        userId: userId,
        attempt: QuestionAttempt(
          questionNumber: 1,
          expression: '(2) + (2)',
          correctAnswer: Rational.fromInt(4),
          selectedAnswer: Rational.fromInt(3),
          isCorrect: false,
          responseTime: Duration(seconds: 3),
          operation: ArithmeticOperation.addition,
          difficulty: ArithmeticDifficulty.beginner,
        ),
        answeredAt: startedAt.add(const Duration(seconds: 3)),
      );
      await sessions.updateLifecycle(
        sessionId: session.id,
        userId: userId,
        update: SessionLifecycleUpdate(
          state: SessionLifecycleState.completed,
          changedAt: startedAt.add(const Duration(seconds: 10)),
          elapsedTime: const Duration(seconds: 10),
          totalPausedTime: Duration.zero,
          endReason: SessionEndReason.questionCountReached,
        ),
      );
      expect(
        (await sessions.getSession(
          sessionId: session.id,
          userId: userId,
        ))!.attempts,
        hasLength(1),
      );

      await tester.pumpWidget(
        _app(PracticeHistoryScreen(repository: sessions, userId: userId)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 questions'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.textContaining('1 questions'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Correct answer: 4'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Question review'), findsOneWidget);
      expect(find.textContaining('Your answer: 3'), findsOneWidget);
      expect(find.textContaining('Correct answer: 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(Widget home) =>
    MaterialApp(theme: ThemeData(useMaterial3: true), home: home);

final class _TestPasswordHasher implements PasswordHasher {
  @override
  Future<String> hash(String password) async => 'test-hash';

  @override
  Future<bool> verify(String password, String encodedHash) async => true;
}
