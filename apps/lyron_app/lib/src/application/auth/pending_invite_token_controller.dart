// apps/lyron_app/lib/src/application/auth/pending_invite_token_controller.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/domain/auth/pending_invite_token.dart';

class PendingInviteTokenController extends ChangeNotifier {
  PendingInviteToken? _current;

  PendingInviteToken? get current => _current;

  void capture(String token) {
    _current = PendingInviteToken(token: token, capturedAt: DateTime.now());
    notifyListeners();
  }

  void clear() {
    _current = null;
    notifyListeners();
  }
}
