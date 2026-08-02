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
class ReauthPromptHost extends ConsumerWidget {
  const ReauthPromptHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ReauthPrompt?>(
      reauthPromptControllerProvider.select((controller) => controller.pending),
      (previous, next) {
        if (next != null) {
          unawaited(_showPrompt(context, ref, next));
        }
      },
    );
    return child;
  }

  Future<void> _showPrompt(
    BuildContext context,
    WidgetRef ref,
    ReauthPrompt prompt,
  ) async {
    final confirmed = await showReauthDifferentUserDialog(
      context,
      email: prompt.email,
      pendingCount: prompt.pendingCount,
    );
    ref.read(reauthPromptControllerProvider).answer(confirmed);
  }
}
