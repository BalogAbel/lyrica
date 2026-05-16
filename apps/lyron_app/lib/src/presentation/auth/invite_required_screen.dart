import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class InviteRequiredScreen extends ConsumerStatefulWidget {
  const InviteRequiredScreen({super.key});

  @override
  ConsumerState<InviteRequiredScreen> createState() =>
      _InviteRequiredScreenState();
}

class _InviteRequiredScreenState extends ConsumerState<InviteRequiredScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingTokens = ref.watch(pendingInviteTokenControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.inviteRequiredTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(AppStrings.inviteRequiredMessage),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: AppStrings.invitePasteLabel,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final raw = _controller.text.trim();
                if (raw.isEmpty) return;
                final token = _extractToken(raw);
                if (token == null) return;
                pendingTokens.capture(token);
              },
              child: const Text(AppStrings.inviteRedeemAction),
            ),
          ],
        ),
      ),
    );
  }

  String? _extractToken(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final token = uri.queryParameters['token'];
    return token?.isEmpty ?? true ? (raw.contains('://') ? null : raw) : token;
  }
}
