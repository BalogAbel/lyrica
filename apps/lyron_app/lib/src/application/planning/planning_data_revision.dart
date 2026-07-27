import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aggregate planning invalidation: the set of plans or a plan summary changed,
/// or a full sync / discard reconciled potentially many plans. Watched by all
/// planning read providers.
final planningDataRevisionProvider = StateProvider<int>((ref) => 0);

/// Pending-mutation invalidation: a local write changed mutation state (a
/// mutation was recorded, synced, discarded, or retried) without necessarily
/// changing the plan set. Watched only by the mutation-facing read providers so
/// a within-plan edit does not rebuild unrelated plan details (ARCH-2). An open
/// OTHER plan's reconciled fields may lag until its next interaction or the next
/// aggregate refresh; this is the intended scoping trade-off.
final planningMutationRevisionProvider = StateProvider<int>((ref) => 0);
