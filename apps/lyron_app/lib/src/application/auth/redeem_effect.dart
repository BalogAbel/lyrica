import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/redeem_controller.dart';
import 'package:lyron_app/src/application/providers.dart';

class RedeemEffect {
  RedeemEffect(this.ref);
  final WidgetRef ref;

  Future<void> tryConsumePending() async {
    final pending = ref.read(pendingInviteTokenControllerProvider);
    final token = pending.current?.token;
    if (token == null) return;

    final controller = ref.read(redeemControllerProvider);
    if (controller.state is RedeemStateInFlight) return;

    await controller.redeem(token);

    if (controller.state is RedeemStateSuccess) {
      pending.clear();
    }
  }
}
