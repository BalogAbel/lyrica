import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/shared/if_capability.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanSongItemRow extends ConsumerWidget {
  const PlanSongItemRow({
    super.key,
    required this.planDetail,
    required this.session,
    required this.item,
    required this.itemIndex,
  });

  final PlanDetail planDetail;
  final SessionSummary session;
  final SessionItemSummary item;
  final int itemIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = ref.watch(activePlanningContextProvider)?.organizationId;
    return Row(
      children: [
        ReorderableDelayedDragStartListener(
          index: itemIndex,
          child: SizedBox(
            key: ValueKey('session-item-drag-handle-${item.id}'),
            width: 40,
            height: 40,
            child: const Center(child: Icon(Icons.drag_indicator)),
          ),
        ),
        Expanded(
          child: InkWell(
            key: ValueKey('plan-session-item-${item.id}'),
            onTap: () {
              context.push(
                PlanningRoutes.planSessionSongReaderLocation(
                  planSlug: planDetail.plan.slug,
                  sessionSlug: session.slug,
                  songSlug: item.song.slug,
                ),
                extra: planDetail,
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: _title()),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
        IfCapability(
          key: Key('session-item-delete-button-${item.id}'),
          capability: Capability.editSessions,
          organizationId: orgId,
          child: IconButton(
            onPressed: () => _deleteItem(context, ref),
            icon: const Icon(Icons.delete_outline),
            tooltip:
                '${AppStrings.sessionItemDeleteAction}: ${item.song.title}',
          ),
        ),
      ],
    );
  }

  /// The row title; with a plan key it also carries the key chips below it
  /// (PS8), so a phone row keeps its title width. A row without a plan value
  /// renders the bare title as before.
  Widget _title() {
    final title = Text('${item.position}. ${item.song.title}');
    final planTranspose = item.planTranspose;
    final planCapo = item.planCapo;
    if (planTranspose == null && planCapo == null) {
      return title;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (planTranspose != null)
              _PlanKeyChip(
                labelKey: ValueKey('plan-session-item-transpose-${item.id}'),
                label: AppStrings.planItemTransposeLabel(planTranspose),
              ),
            if (planCapo != null)
              _PlanKeyChip(
                labelKey: ValueKey('plan-session-item-capo-${item.id}'),
                label: AppStrings.planItemCapoLabel(planCapo),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _deleteItem(BuildContext context, WidgetRef ref) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }
    await ref
        .read(planningWriteServiceProvider)
        .deleteSessionItem(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: SessionItemDeleteDraft(
            sessionItemId: item.id,
            sessionId: session.id,
            planId: planDetail.plan.id,
          ),
        );
    if (!context.mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planDetail.plan.id));
  }
}

/// A small plan-value chip. [labelKey] sits on the label [Text], so the keyed
/// widget carries the chip's text itself.
class _PlanKeyChip extends StatelessWidget {
  const _PlanKeyChip({required this.labelKey, required this.label});

  final Key labelKey;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          key: labelKey,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
