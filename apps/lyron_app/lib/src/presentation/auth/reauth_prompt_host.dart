import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/auth_providers.dart';
import 'package:lyron_app/src/presentation/auth/reauth_different_user_dialog.dart';

/// Mounted in `MaterialApp.router`'s `builder:`, wrapping the routed child.
///
/// There is no navigator key and no shell route in this app (see ADR-029) --
/// this host is where the different-user reauth prompt gets somewhere to
/// run.
///
/// `build` never watches [reauthPromptControllerProvider]; it only
/// `ref.listen`s to it. That means a new pending prompt never rebuilds this
/// widget (and so never rebuilds [child] or anything below it) -- the
/// listener callback shows the dialog imperatively and feeds the answer
/// back, entirely outside the widget tree's rebuild cycle.
class ReauthPromptHost extends ConsumerStatefulWidget {
  const ReauthPromptHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReauthPromptHost> createState() => _ReauthPromptHostState();
}

class _ReauthPromptHostState extends ConsumerState<ReauthPromptHost> {
  ProviderSubscription<ReauthPrompt?>? _subscription;
  int? _activeRequestId;

  /// Whether this host currently has a dialog route pushed for
  /// [_activeRequestId]. Tracked explicitly rather than inferred from
  /// Navigator state so a supersession can pop exactly the route this host
  /// pushed -- never a route pushed by someone else.
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _subscription = ref.listenManual<ReauthPrompt?>(
      reauthPromptControllerProvider.select((controller) => controller.pending),
      (previous, next) {
        if (next == null) {
          // Supersession (or an answer) cleared the pending prompt. Drop the
          // stale request id and pop whatever dialog this host still has
          // open for it -- ADR-029 promises supersession "clears any open
          // prompt", so a superseded prompt must never linger on screen for
          // the next one to stack on top of.
          _activeRequestId = null;
          _closeOpenDialog();
          return;
        }
        if (next.requestId != _activeRequestId) {
          _activeRequestId = next.requestId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _activeRequestId != next.requestId) return;
            final pending = ref.read(reauthPromptControllerProvider).pending;
            if (pending?.requestId != next.requestId) return;
            unawaited(_showPrompt(context, ref, next));
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void _closeOpenDialog() {
    if (!_dialogOpen || !mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _showPrompt(
    BuildContext context,
    WidgetRef ref,
    ReauthPrompt prompt,
  ) async {
    _dialogOpen = true;
    final bool confirmed;
    try {
      confirmed = await showReauthDifferentUserDialog(
        context,
        email: prompt.email,
        pendingCount: prompt.pendingCount,
      );
    } finally {
      _dialogOpen = false;
    }
    if (!mounted) return;
    // Superseded requests are already cleared (and their dialog already
    // popped) by the listener above, so this answer targets a stale
    // requestId and the controller's own id check turns it into a no-op --
    // it never reaches a newer prompt.
    ref
        .read(reauthPromptControllerProvider)
        .answer(confirmed, requestId: prompt.requestId);
    if (_activeRequestId == prompt.requestId) {
      _activeRequestId = null;
    }
  }
}
