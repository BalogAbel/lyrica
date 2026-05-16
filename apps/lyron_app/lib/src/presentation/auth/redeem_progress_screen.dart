import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/redeem_controller.dart';
import 'package:lyron_app/src/application/auth/redeem_effect.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class RedeemProgressScreen extends ConsumerStatefulWidget {
  const RedeemProgressScreen({super.key});

  @override
  ConsumerState<RedeemProgressScreen> createState() =>
      _RedeemProgressScreenState();
}

class _RedeemProgressScreenState extends ConsumerState<RedeemProgressScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RedeemEffect(ref).tryConsumePending();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(redeemControllerProvider).state;

    return Scaffold(
      body: Center(
        child: switch (state) {
          RedeemStateIdle() ||
          RedeemStateInFlight() => const CircularProgressIndicator(),
          RedeemStateSuccess() => const SizedBox.shrink(),
          RedeemStateFailure(:final error) => Text(_messageFor(error)),
        },
      ),
    );
  }

  String _messageFor(InvitationError error) => switch (error) {
        InvitationError.notFound => AppStrings.inviteErrorNotFound,
        InvitationError.expired => AppStrings.inviteErrorExpired,
        InvitationError.alreadyRedeemed => AppStrings.inviteErrorAlreadyRedeemed,
        InvitationError.alreadyMember => AppStrings.inviteErrorAlreadyMember,
        InvitationError.network ||
        InvitationError.unknown => AppStrings.inviteErrorNotFound,
      };
}
