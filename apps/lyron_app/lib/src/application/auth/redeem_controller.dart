// apps/lyron_app/lib/src/application/auth/redeem_controller.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';

sealed class RedeemState {
  const RedeemState();
}

class RedeemStateIdle extends RedeemState {
  const RedeemStateIdle();
}

class RedeemStateInFlight extends RedeemState {
  const RedeemStateInFlight();
}

class RedeemStateSuccess extends RedeemState {
  const RedeemStateSuccess(this.organizationId);
  final String organizationId;
}

class RedeemStateFailure extends RedeemState {
  const RedeemStateFailure(this.error);
  final InvitationError error;
}

class RedeemController extends ChangeNotifier {
  RedeemController(this._repository);

  final InvitationRepository _repository;
  RedeemState _state = const RedeemStateIdle();

  RedeemState get state => _state;

  Future<void> redeem(String token) async {
    _set(const RedeemStateInFlight());
    final result = await _repository.redeem(token);
    switch (result) {
      case RedeemSuccess(:final organizationId):
        _set(RedeemStateSuccess(organizationId));
      case RedeemFailure(:final error):
        _set(RedeemStateFailure(error));
    }
  }

  void reset() => _set(const RedeemStateIdle());

  void _set(RedeemState next) {
    _state = next;
    notifyListeners();
  }
}
