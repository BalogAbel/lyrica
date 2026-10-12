import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_status_popup.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class UnifiedSyncHeaderControl extends StatelessWidget {
  const UnifiedSyncHeaderControl({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      return const SizedBox.shrink(
        key: ValueKey('unified-sync-header-control'),
      );
    }
    return const _UnifiedSyncHeaderControlBody();
  }
}

class _UnifiedSyncHeaderControlBody extends ConsumerWidget {
  const _UnifiedSyncHeaderControlBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(unifiedSyncOverviewProvider);
    final (label, color) = _labelAndColor(context, overview.headerStatus);
    final secondary = _secondaryText(overview);
    final tooltip = secondary == null ? label : '$label · $secondary';
    // SG7: offline-cached or stale data must be visible without opening the
    // popup. The pending-work colour keeps its meaning; the dot turns hollow.
    final notFresh =
        overview.freshness == UnifiedSyncFreshness.stale ||
        overview.freshness == UnifiedSyncFreshness.offlineCached;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: const ValueKey('unified-sync-header-control'),
        onTap: () => UnifiedSyncStatusPopup.show(context),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          // 18 padding + 12 dot = 48x48 minimum touch target (Material a11y).
          padding: const EdgeInsets.all(18),
          child: Container(
            key: ValueKey(
              notFresh
                  ? 'unified-sync-header-dot-hollow'
                  : 'unified-sync-header-dot-filled',
            ),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: notFresh ? Colors.transparent : color,
              shape: BoxShape.circle,
              border: notFresh ? Border.all(color: color, width: 2) : null,
            ),
          ),
        ),
      ),
    );
  }

  (String, Color) _labelAndColor(
    BuildContext context,
    UnifiedSyncHeaderStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      UnifiedSyncHeaderStatus.synced => (
        AppStrings.unifiedSyncSyncedLabel,
        Colors.green.shade700,
      ),
      UnifiedSyncHeaderStatus.unsynced => (
        AppStrings.unifiedSyncUnsyncedLabel,
        Colors.amber.shade800,
      ),
      UnifiedSyncHeaderStatus.conflict => (
        AppStrings.unifiedSyncConflictLabel,
        scheme.error,
      ),
    };
  }

  String? _secondaryText(UnifiedSyncOverview overview) {
    final parts = <String>[];
    final freshness = switch (overview.freshness) {
      UnifiedSyncFreshness.fresh => null,
      UnifiedSyncFreshness.stale => AppStrings.unifiedSyncFreshnessStale,
      UnifiedSyncFreshness.offlineCached =>
        AppStrings.unifiedSyncFreshnessOfflineCached,
      UnifiedSyncFreshness.unknown => null,
    };
    if (freshness != null) parts.add(freshness);
    if (overview.activity == UnifiedSyncActivity.syncing) {
      parts.add(AppStrings.unifiedSyncActivitySyncing);
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }
}
