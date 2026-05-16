import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/invite_required_screen.dart';

void main() {
  testWidgets('extracts token from pasted invite URL', (tester) async {
    final pending = PendingInviteTokenController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingInviteTokenControllerProvider.overrideWith((_) => pending),
        ],
        child: const MaterialApp(home: InviteRequiredScreen()),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField),
      'https://app.lyron.example/invite?token=ABCDEF',
    );
    await tester.tap(find.text('Redeem invite'));
    await tester.pump();

    expect(pending.current?.token, 'ABCDEF');
  });
}
