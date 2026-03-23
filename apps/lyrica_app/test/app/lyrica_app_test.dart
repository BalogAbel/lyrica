import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/app/lyrica_app.dart';
import 'package:lyrica_app/src/application/auth/auth_repository.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';

void main() {
  testWidgets(
    'shows auth bootstrap loading before session restoration completes',
    (tester) async {
      final completer = Completer<AppAuthSession?>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              _DelayedAuthRepository(completer.future),
            ),
          ],
          child: LyricaApp(),
        ),
      );
      await tester.pump();

      expect(find.text('Restoring session...'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);

      completer.complete(null);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('boots into sign in through the shared app router', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_TestAuthRepository()),
        ],
        child: LyricaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lyrica'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('A forrásnál'), findsNothing);
    expect(find.text('A mi Istenünk (Leborulok előtted)'), findsNothing);
    expect(find.text('Egy út'), findsNothing);
  });
}

class _TestAuthRepository implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async => null;

  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async => AppAuthSession(userId: 'user-1', email: email);

  @override
  Future<void> signOut() async {}
}

class _DelayedAuthRepository implements AuthRepository {
  _DelayedAuthRepository(this._restoreFuture);

  final Future<AppAuthSession?> _restoreFuture;

  @override
  Future<AppAuthSession?> restoreSession() => _restoreFuture;

  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async => AppAuthSession(userId: 'user-1', email: email);

  @override
  Future<void> signOut() async {}
}
