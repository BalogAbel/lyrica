// SG8 (docs/specs/2026-10-05-offline-first-startup-gate.md): the startup
// path with the REAL auth client. Every other offline startup test replaces
// the membership and session readers with fakes that answer instantly, which
// is exactly why the 10-15 s gate wait (G-A) was never caught.
//
// The HTTP client never completes a request: a connection that opens and
// never answers, the worst real network shape. It is also the only shape
// that is deterministic under widget-test fake time: gotrue's refresh retry
// loop measures elapsed time with the real DateTime.now() while its back-off
// delays are fake timers, so a failing client makes the loop endless here.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/shared/app_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_test_setup.dart';

class _HangingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

String _jwt({required int expiresAtSeconds}) {
  String encode(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'sub': 'user-1', 'exp': expiresAtSeconds})}.signature';
}

/// A persisted session whose access token expired five hours ago -- what a
/// device holds after a long idle period (jwt_expiry is 3600 s).
String _expiredSessionJson() {
  final issuedAt = DateTime.now().subtract(const Duration(hours: 5));
  return jsonEncode({
    'access_token': _jwt(
      expiresAtSeconds: issuedAt.millisecondsSinceEpoch ~/ 1000,
    ),
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-1',
    'user': {
      'id': 'user-1',
      'aud': 'authenticated',
      'email': 'demo@lyron.local',
      'app_metadata': <String, Object>{},
      'user_metadata': <String, Object>{},
      'created_at': issuedAt.toIso8601String(),
    },
  });
}

class _Fixture {
  _Fixture()
    : songDatabase = SongCatalogDatabase.inMemory(),
      identityDatabase = LastKnownIdentityDatabase.inMemory(),
      client = SupabaseClient(
        'https://test.supabase.co',
        'anon-key',
        httpClient: _HangingHttpClient(),
      );

  final SongCatalogDatabase songDatabase;
  final LastKnownIdentityDatabase identityDatabase;
  final SupabaseClient client;

  Future<void> seed(
    WidgetTester tester, {
    required bool persistedSession,
  }) async {
    await tester.runAsync(() async {
      await DriftSongCatalogStore(songDatabase).replaceActiveSnapshot(
        userId: 'user-1',
        organizationId: 'org-1',
        summaries: const [
          SongSummary(id: 'song-1', slug: 'egy-ut', title: 'Egy út'),
        ],
        sources: const [SongSource(id: 'song-1', source: '{title:Egy út}\n')],
        refreshedAt: DateTime.utc(2026, 10, 1),
      );
      await DriftLastKnownIdentityStore(identityDatabase).write(
        const LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
        ),
      );
      if (persistedSession) {
        await client.auth.setInitialSession(_expiredSessionJson());
      }
    });
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      isolatedSongCatalogProviderScope(
        songCatalogDatabase: songDatabase,
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          lastKnownIdentityDatabaseProvider.overrideWithValue(identityDatabase),
        ],
        child: LyronApp(),
      ),
    );
    // One second of fake time: far below gotrue's 10 s refresh budget, so
    // nothing asserted below may depend on the network.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tearDown(WidgetTester tester) async {
    // Never dispose the client here: dispose completes the hung refresh with
    // an error, and the app code waiting on it would resume after its
    // providers are gone.
    client.auth.stopAutoRefresh();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      await songDatabase.close();
      await identityDatabase.close();
    });
  }
}

void main() {
  suppressDriftMultipleDatabaseWarnings();

  testWidgets(
    'signed in with an expired token on a hung network: the cached song '
    'list is the first screen (G-A)',
    (tester) async {
      final fixture = _Fixture();
      await fixture.seed(tester, persistedSession: true);
      await fixture.pumpApp(tester);

      expect(
        find.text(AppStrings.membershipConnectivityFailureMessage),
        findsNothing,
      );
      expect(find.text('Egy út'), findsOneWidget);

      await fixture.tearDown(tester);
    },
    skip: true, // S0 Task 7 removes this
  );

  testWidgets(
    'cold start straight into sessionExpired: the cached song list and the '
    're-auth banner are the first screen (G-B)',
    (tester) async {
      final fixture = _Fixture();
      await fixture.seed(tester, persistedSession: false);
      await fixture.pumpApp(tester);

      expect(
        find.text(AppStrings.membershipConnectivityFailureMessage),
        findsNothing,
      );
      expect(find.text('Egy út'), findsOneWidget);
      expect(find.byKey(const ValueKey('reauth-banner')), findsOneWidget);

      await fixture.tearDown(tester);
    },
    skip: true, // S0 Task 7 removes this
  );
}
