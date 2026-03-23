import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/app/lyrica_app.dart';
import 'package:lyrica_app/src/application/auth/auth_repository.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/infrastructure/song_library/supabase_song_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'boots into the signed-in song list, opens the reader, and redirects to sign in when the session expires',
    (tester) async {
      final authRepository = _StreamingAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyrica.local',
        ),
      );
      final songRepository = SupabaseSongRepository.testing(
        listSongsRows: () async => [
          {'id': 'egy_ut', 'title': 'Egy út'},
        ],
        getSongRow: (id) async => {
          'id': id,
          'chordpro_source':
              '{title:Egy út}\n'
              '{subtitle:One Way}\n'
              '{key:B}\n'
              '{comment:<Verse 1>}\n'
              '[B] Leteszem az eletem\n',
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(authRepository),
            supabaseSongRepositoryProvider.overrideWithValue(songRepository),
          ],
          child: LyricaApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lyrica'), findsOneWidget);
      expect(find.text('Egy út'), findsOneWidget);

      await tester.tap(find.text('Egy út'));
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsOneWidget);
      expect(find.text('Egy út'), findsWidgets);
      expect(find.text('One Way'), findsOneWidget);
      expect(find.text('Key: B'), findsOneWidget);
      expect(find.text('Verse 1'), findsOneWidget);
      expect(find.textContaining('Leteszem'), findsWidgets);

      authRepository.expireSession();
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(
        find.text('Your session expired. Please sign in again.'),
        findsOneWidget,
      );
    },
  );
}

class _StreamingAuthRepository implements AuthRepository {
  _StreamingAuthRepository({this.restoredSession});

  final AppAuthSession? restoredSession;
  final _controller = StreamController<AppAuthSession?>.broadcast();

  void expireSession() {
    _controller.add(null);
  }

  @override
  Future<AppAuthSession?> restoreSession() async => restoredSession;

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final session = AppAuthSession(userId: 'user-1', email: email);
    _controller.add(session);
    return session;
  }

  @override
  Future<void> signOut() async {
    _controller.add(null);
  }
}
