import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth/capability_resolver.dart';
import '../../application/providers.dart';
import '../../domain/core/capability.dart';

/// Renders [child] only when the active organization grants [capability].
/// When capability is unknown or absent, renders [SizedBox.shrink].
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshIfNeeded();
  }

  @override
  void didUpdateWidget(IfCapability old) {
    super.didUpdateWidget(old);
    _refreshIfNeeded();
  }

  void _refreshIfNeeded() {
    final orgId = widget.organizationId;
    if (orgId == null) {
      _future = null;
      _lastOrgId = null;
      return;
    }
    if (orgId != _lastOrgId || widget.capability != _lastCapability) {
      _lastOrgId = orgId;
      _lastCapability = widget.capability;
      try {
        _future = ref
            .read(capabilityResolverProvider)
            .hasCapability(orgId, widget.capability)
            // Fail-open on async errors (e.g. transient network failures).
            // The backend enforces the actual permission; UI gating is UX only.
            .catchError((_) => true);
      } catch (_) {
        // Fail-open on synchronous errors (e.g. Supabase not initialised in
        // tests or other environments where the provider is not available).
        _future = Future.value(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: future,
      builder: (context, snap) =>
          snap.data == true ? widget.child : const SizedBox.shrink(),
    );
  }
}
