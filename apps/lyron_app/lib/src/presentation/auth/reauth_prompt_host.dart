import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/auth_providers.dart';
import 'package:lyron_app/src/presentation/auth/membership_revocation_purge_dialog.dart';
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
  /// Navigator state, so the host only ever pops while one of its own
  /// dialogs is open.
  ///
  /// `showDialog` does not hand back the route it pushed, so the pop below
  /// removes the top-most route rather than that specific one. The reauth
  /// dialog is modal and blocks interaction beneath it, so in practice
  /// nothing of the app's own is pushed above it while it is open.
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
    // YELLOW 10 (final whole-branch review): captured now, while the widget
    // is certainly still mounted, so it can still be used to answer the
    // completer below even if the widget is unmounted by the time the
    // dialog await returns. `ref` itself must not be touched again after an
    // unmount -- reading through it post-dispose is unsafe -- but this
    // controller reference is just a plain object and outlives the widget
    // (it is app-scoped and NOT autoDispose; see the class doc on
    // ReauthPromptController).
    final promptController = ref.read(reauthPromptControllerProvider);
    final bool confirmed;
    try {
      switch (prompt) {
        case ReauthDifferentUserPrompt():
          confirmed = await showReauthDifferentUserDialog(
            context,
            email: prompt.email,
            pendingCount: prompt.pendingCount,
          );
        case MembershipRevocationPurgePrompt():
          confirmed = await showMembershipRevocationPurgeDialog(
            context,
            pendingCount: prompt.pendingCount,
          );
      }
    } finally {
      _dialogOpen = false;
    }
    if (!mounted) {
      // YELLOW 10 fix: an unmounted host must still answer the completer
      // this prompt is backing -- leaving it unanswered means every caller
      // awaiting it (D5 newly routes some of these through callers that
      // hold outer locks, e.g. SongCatalogController._refreshFuture and
      // lastKnownIdentityPersistenceProvider's resolution chain) stays
      // blocked until the next supersedePending. Not confirmed: an unmount
      // mid-dialog is not a user answer.
      promptController.answer(false, requestId: prompt.requestId);
      return;
    }
    // For a live request this resolves the pending future with the user's
    // answer. If [prompt] was superseded instead -- the listener above
    // already cleared and popped it before this await returned -- the
    // controller's own requestId check turns this into a no-op: it can
    // never resolve or otherwise touch a newer prompt.
    promptController.answer(confirmed, requestId: prompt.requestId);
    if (_activeRequestId == prompt.requestId) {
      _activeRequestId = null;
    }
  }
}
