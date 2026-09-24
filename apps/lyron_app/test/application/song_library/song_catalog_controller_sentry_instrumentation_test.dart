import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/song/song_repository.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_observability.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Drives a real [SongCatalogController] with the real [SentryObservability]
/// adapter against an in-memory Sentry (recording transport, no network) and
/// asserts the captured transaction shape from
/// docs/specs/2026-08-28-observability-foundation.md. The sibling
/// 'observability instrumentation' group in song_catalog_controller_test.dart
/// uses a recording double and therefore never produces a real span.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SongCatalogDatabase database;
  late DriftSongCatalogStore store;
  late _FakeSongRepository remoteRepository;
  late LocalDataLifecycle lifecycle;
  late List<SentryTransaction> transactions;
  late List<SentryEvent> events;
  late List<String> httpAttempts;
  late Completer<SentryTransaction> firstTransaction;

  setUp(() async {
    database = SongCatalogDatabase.inMemory();
    store = DriftSongCatalogStore(database);
    remoteRepository = _FakeSongRepository();
    lifecycle = LocalDataLifecycle(
      songCatalogStore: store,
      planningLocalStore: _NoopPlanningLocalStore(),
      identityStore: _NoopLastKnownIdentityStore(),
      noteLastKnownIdentity: (_) {},
      eventsRecorder: _NoopLocalDataEventsRecorder(),
    );
    transactions = [];
    events = [];
    httpAttempts = [];
    firstTransaction = Completer<SentryTransaction>();
    // Global (not `runZoned`): the SDK builds its HTTP client during
    // `Sentry.init`, so the override must already be installed then.
    HttpOverrides.global = _FailingHttpOverrides(httpAttempts);
    await Sentry.init((options) {
      // Syntactically valid dummy DSN. The recording transport below is what
      // keeps everything in memory: a NoOpTransport would be swapped for a
      // real HttpTransport by SentryClient as soon as a DSN is set.
      options.dsn = 'https://public@o0.ingest.sentry.io/0';
      options.tracesSampleRate = 1.0;
      options.transport = _RecordingTransport();
      options.beforeSendTransaction = (transaction) {
        transactions.add(transaction);
        if (!firstTransaction.isCompleted) {
          firstTransaction.complete(transaction);
        }
        return transaction;
      };
      options.beforeSend = (event, hint) {
        events.add(event);
        return event;
      };
    });
  });

  tearDown(() async {
    await Sentry.close();
    HttpOverrides.global = null;
    await database.close();
  });

  SongCatalogController buildController() {
    final controller = SongCatalogController(
      store: store,
      localDataLifecycle: lifecycle,
      remoteRepository: remoteRepository,
      authSessionReader: () =>
          const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      organizationReader: () async => 'org-1',
      sessionVerifier: () async => CatalogSessionStatus.verified,
      onImplausibleEmptySnapshot:
          ({required userId, required organizationId}) async {},
      observability: const SentryObservability(),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// Transaction finish is fire-and-forget (SentryObservability.runInSpan),
  /// so `refreshCatalog()` completing does not mean the transaction was
  /// delivered. Wait on the completer `beforeSendTransaction` fires -- never
  /// a timed guess.
  Future<SentryTransaction> deliveredTransaction() =>
      firstTransaction.future.timeout(const Duration(seconds: 10));

  /// Lets any straggling Sentry work (an issue event, a second transaction)
  /// surface before a "nothing else happened" assertion.
  Future<void> pump() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Map<String, SentrySpan> spansByName(SentryTransaction tx) => {
    for (final span in tx.spans) span.context.description!: span,
  };

  test('a successful refresh yields one trace: a business.refresh root with '
      'every documented child span, all ok', () async {
    final controller = buildController();

    await controller.refreshCatalog();
    final tx = await deliveredTransaction();
    await pump();

    expect(controller.state.refreshStatus, CatalogRefreshStatus.idle);
    expect(transactions, hasLength(1));
    expect(tx.transaction, 'song_catalog.refresh');
    final rootContext = tx.contexts.trace!;
    expect(rootContext.operation, 'business.refresh');
    expect(rootContext.status, const SpanStatus.ok());

    final byName = spansByName(tx);
    expect(byName.keys, {
      'membership.resolve',
      'auth.verify_session',
      'song_catalog.list_songs',
      'song_catalog.fetch_sources',
      'song_catalog.write_snapshot',
    });
    expect(tx.spans, hasLength(5), reason: 'no duplicate or stray spans');

    const expectedOperations = {
      'membership.resolve': 'http.client',
      'auth.verify_session': 'http.client',
      'song_catalog.list_songs': 'http.client',
      'song_catalog.fetch_sources': 'http.client',
      'song_catalog.write_snapshot': 'db.write',
    };
    for (final entry in expectedOperations.entries) {
      final span = byName[entry.key]!;
      expect(span.context.operation, entry.value, reason: entry.key);
      expect(span.status, const SpanStatus.ok(), reason: entry.key);
      // Same trace as the root, parented directly to the root.
      expect(span.context.traceId, rootContext.traceId, reason: entry.key);
      expect(span.context.parentSpanId, rootContext.spanId, reason: entry.key);
    }
    expect(events, isEmpty, reason: 'a successful refresh files no issue');
    expect(httpAttempts, isEmpty);
  });

  test('a listSongs failure the controller classifies and swallows: '
      'list_songs is internalError, the root stays ok (the exception never '
      'propagates out of the root span body), later spans never start, and '
      'no Sentry issue is captured', () async {
    remoteRepository.listSongsError = Exception('boom');
    final controller = buildController();

    // Swallowed by the controller: refreshCatalog() itself completes.
    await controller.refreshCatalog();
    final tx = await deliveredTransaction();
    await pump();

    expect(controller.state.refreshStatus, CatalogRefreshStatus.failed);
    expect(transactions, hasLength(1));
    expect(tx.transaction, 'song_catalog.refresh');
    expect(tx.contexts.trace!.operation, 'business.refresh');
    expect(
      tx.contexts.trace!.status,
      const SpanStatus.ok(),
      reason:
          'the catch in _refreshCatalogBody handles the error, so the '
          'root span body completes normally',
    );

    final byName = spansByName(tx);
    expect(byName.keys, {
      'membership.resolve',
      'auth.verify_session',
      'song_catalog.list_songs',
    });
    expect(byName['membership.resolve']!.status, const SpanStatus.ok());
    expect(byName['auth.verify_session']!.status, const SpanStatus.ok());
    final listSongs = byName['song_catalog.list_songs']!;
    expect(listSongs.context.operation, 'http.client');
    expect(listSongs.status, const SpanStatus.internalError());
    expect(listSongs.context.traceId, tx.contexts.trace!.traceId);
    expect(listSongs.context.parentSpanId, tx.contexts.trace!.spanId);

    expect(
      events,
      isEmpty,
      reason:
          'span status is a marker, not an issue: an instrumented failure '
          'must never file a Sentry issue',
    );
    expect(httpAttempts, isEmpty);
  });
}

/// Recording fake [Transport]: nothing ever leaves the machine.
class _RecordingTransport implements Transport {
  final envelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return null;
  }
}

class _FailingHttpOverrides extends HttpOverrides {
  _FailingHttpOverrides(this.attempted);

  final List<String> attempted;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FailingHttpClient(attempted);
}

class _FailingHttpClient implements HttpClient {
  _FailingHttpClient(this.attempted);

  /// Names of every `HttpClient` member touched.
  final List<String> attempted;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    attempted.add(invocation.memberName.toString());
    throw StateError('network attempted in offline test');
  }
}

class _FakeSongRepository implements SongRepository {
  Object? listSongsError;

  @override
  Future<List<SongSummary>> listSongs() async {
    final error = listSongsError;
    if (error != null) {
      throw error;
    }
    return const [
      SongSummary(id: 'song-1', title: 'Alpha'),
      SongSummary(id: 'song-2', title: 'Beta'),
    ];
  }

  @override
  Future<SongSource> getSongSource(String id) async =>
      SongSource(id: id, source: '{title: $id}');
}

// Trivial LocalDataLifecycle deps: SongCatalogController never calls them in
// a refresh, so the noSuchMethod forwarding is unreachable in practice.
class _NoopPlanningLocalStore implements PlanningLocalStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLastKnownIdentityStore implements LastKnownIdentityStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLocalDataEventsRecorder implements LocalDataEventsRecorder {
  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  }) async {}
  @override
  Future<void> recordStorageWriteFailure({String? userId}) async {}

  @override
  Future<void> recordMembershipRevocationMarked({
    required String userId,
  }) async {}

  @override
  Future<void> recordMembershipRevocationCleared({
    required String userId,
  }) async {}

  @override
  Future<void> recordMembershipRevocationPurgeDeclined({
    required String userId,
    required MembershipRevocationPurgeDeclineReason reason,
  }) async {}
}
