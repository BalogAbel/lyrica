import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';

class CatalogSnapshotState {
  const CatalogSnapshotState({
    required this.context,
    required this.connectionStatus,
    required this.refreshStatus,
    required this.sessionStatus,
    required this.hasCachedCatalog,
  });

  const CatalogSnapshotState.initial()
    : this(
        context: null,
        connectionStatus: CatalogConnectionStatus.unavailable,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: false,
      );

  final ActiveCatalogContext? context;
  final CatalogConnectionStatus connectionStatus;
  final CatalogRefreshStatus refreshStatus;
  final CatalogSessionStatus sessionStatus;
  final bool hasCachedCatalog;

  CatalogSnapshotState copyWith({
    ActiveCatalogContext? context,
    bool clearContext = false,
    CatalogConnectionStatus? connectionStatus,
    CatalogRefreshStatus? refreshStatus,
    CatalogSessionStatus? sessionStatus,
    bool? hasCachedCatalog,
  }) {
    return CatalogSnapshotState(
      context: clearContext ? null : (context ?? this.context),
      connectionStatus: connectionStatus ?? this.connectionStatus,
      refreshStatus: refreshStatus ?? this.refreshStatus,
      sessionStatus: sessionStatus ?? this.sessionStatus,
      hasCachedCatalog: hasCachedCatalog ?? this.hasCachedCatalog,
    );
  }
}
