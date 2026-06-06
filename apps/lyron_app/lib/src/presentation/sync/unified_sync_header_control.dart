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

    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: const ValueKey('unified-sync-header-control'),
        onTap: () => UnifiedSyncStatusPopup.show(context),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
