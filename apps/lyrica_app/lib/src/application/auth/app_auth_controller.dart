import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyrica_app/src/application/auth/app_auth_state.dart';
import 'package:lyrica_app/src/application/auth/auth_repository.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_status.dart';

class AppAuthController extends ChangeNotifier {
  AppAuthController(this._repository)
    : _state = const AppAuthState(status: AppAuthStatus.initializing);

  final AuthRepository _repository;

  AppAuthState _state;
  StreamSubscription<AppAuthSession?>? _subscription;
  bool _isSigningOut = false;

  AppAuthState get state => _state;

  Future<void> restoreSession() async {
    _subscription ??= _repository.watchSession().listen(_handleSessionUpdate);

    final session = await _repository.restoreSession();
    _setState(_stateForSession(session, fromStream: false));
  }

  Future<void> signIn({required String email, required String password}) async {
    _subscription ??= _repository.watchSession().listen(_handleSessionUpdate);

    final session = await _repository.signIn(email: email, password: password);
    _setState(AppAuthState(status: AppAuthStatus.signedIn, session: session));
  }

  Future<void> signOut() async {
    _isSigningOut = true;
    try {
      await _repository.signOut();
      _setState(const AppAuthState(status: AppAuthStatus.signedOut));
    } finally {
      _isSigningOut = false;
    }
  }

  void _handleSessionUpdate(AppAuthSession? session) {
    _setState(_stateForSession(session, fromStream: true));
  }

  AppAuthState _stateForSession(
    AppAuthSession? session, {
    required bool fromStream,
  }) {
    if (session != null) {
      return AppAuthState(status: AppAuthStatus.signedIn, session: session);
    }

    if (fromStream &&
        !_isSigningOut &&
        _state.status == AppAuthStatus.signedIn) {
      return const AppAuthState(status: AppAuthStatus.sessionExpired);
    }

    return const AppAuthState(status: AppAuthStatus.signedOut);
  }

  void _setState(AppAuthState nextState) {
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
