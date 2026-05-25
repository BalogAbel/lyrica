import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth/capability_resolver.dart';
import '../../application/providers.dart';
import '../../domain/core/capability.dart';

/// Renders [child] only when the active organization grants [capability].
/// When capability is unknown or absent, renders [SizedBox.shrink].
///
/// Fail-open: if the resolver is unavailable (e.g. Supabase not initialised
/// in tests, or a transient network error), the child is shown — the backend
/// enforces the actual permission; this widget is a UX affordance only.
class IfCapability extends ConsumerStatefulWidget {
  const IfCapability({
    super.key,
    required this.capability,
    required this.organizationId,
    required this.child,
  });

  final Capability capability;
  final String? organizationId;
  final Widget child;

  @override
  ConsumerState<IfCapability> createState() => _IfCapabilityState();
}

class _IfCapabilityState extends ConsumerState<IfCapability> {
  Future<bool>? _future;
  String? _lastOrgId;
  Capability? _lastCapability;
  int? _lastVersion;

  @override
  Widget build(BuildContext context) {
    // Watch the resolver so this widget rebuilds when invalidate() fires
    // (e.g. after an auth state change or a role upgrade via invitation).
    CapabilityResolver resolver;
    try {
      resolver = ref.watch(capabilityResolverProvider);
    } catch (_) {
      // Fail-open: resolver unavailable (e.g. Supabase not initialised).
      return widget.child;
    }

    final orgId = widget.organizationId;
    final version = resolver.version;

    // Re-create the future only when orgId, capability, or resolver version
    // changes. Preserving _future across unrelated parent rebuilds prevents
    // the child from flashing hidden while the new future resolves.
    if (orgId != _lastOrgId ||
        widget.capability != _lastCapability ||
        version != _lastVersion) {
      _lastOrgId = orgId;
      _lastCapability = widget.capability;
      _lastVersion = version;
      _future = orgId == null
          ? null
          : resolver
              .hasCapability(orgId, widget.capability)
              // Fail-open on async errors (e.g. transient network failures).
              .catchError((_) => true);
    }

    final future = _future;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: future,
      builder: (context, snap) =>
          snap.data == true ? widget.child : const SizedBox.shrink(),
    );
  }
}
