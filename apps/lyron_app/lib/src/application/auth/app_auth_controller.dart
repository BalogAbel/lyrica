import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';

class AppAuthController extends ChangeNotifier {
  AppAuthController(
    this._repository, {
    LastKnownIdentityStore? lastKnownIdentityStore,
  }) : _lastKnownIdentityStore = lastKnownIdentityStore,
       _state = const AppAuthState(status: AppAuthStatus.initializing);

  final AuthRepository _repository;
  final LastKnownIdentityStore? _lastKnownIdentityStore;

  AppAuthState _state;
  StreamSubscription<AppAuthSession?>? _subscription;
  bool _isSigningOut = false;
  bool _isDisposed = false;
  int _authGeneration = 0;

  AppAuthState get state => _state;

  Future<void> restoreSession() async {
    _subscription ??= _repository.watchSession().listen(_handleSessionUpdate);
    final generation = _authGeneration;
    final session = await _repository.restoreSession();
    final nextState = await _stateForRestoredSession(session);
    if (generation == _authGeneration) {
      _setState(nextState);
    }
  }

  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {
    _subscription ??= _repository.watchSession().listen(_handleSessionUpdate);
    await _repository.signInWithOAuth(method, redirectTo: redirectTo);
  }

  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {
    _subscription ??= _repository.watchSession().listen(_handleSessionUpdate);
    await _repository.sendMagicLink(email: email, redirectTo: redirectTo);
  }

  Future<void> signOut() async {
    _authGeneration += 1;
    _isSigningOut = true;
    try {
      await _repository.signOut();
      _setState(const AppAuthState(status: AppAuthStatus.signedOut));
    } finally {
      _isSigningOut = false;
    }
  }

  Future<void> deleteAccount() async {
    _authGeneration += 1;
    _isSigningOut = true;
    try {
      await _repository.deleteAccount();
      _setState(const AppAuthState(status: AppAuthStatus.signedOut));
    } finally {
      _isSigningOut = false;
    }
  }

  void _handleSessionUpdate(AppAuthSession? session) {
    _authGeneration += 1;
    _setState(_stateForSession(session, fromStream: true));
  }

  Future<AppAuthState> _stateForRestoredSession(
    AppAuthSession? session,
  ) async {
    if (session != null) {
      return AppAuthState(status: AppAuthStatus.signedIn, session: session);
    }
    final identityStore = _lastKnownIdentityStore;
    if (identityStore == null) {
      return const AppAuthState(status: AppAuthStatus.signedOut);
    }
    final identity = await identityStore.read();
    if (identity == null) {
      return const AppAuthState(status: AppAuthStatus.signedOut);
    }
    return AppAuthState(
      status: AppAuthStatus.sessionExpired,
      lastKnownSession: AppAuthSession(
        userId: identity.userId,
        email: identity.email,
        linkedProviders: const [],
      ),
    );
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
      return AppAuthState(
        status: AppAuthStatus.sessionExpired,
        lastKnownSession: _state.session,
      );
    }
    return const AppAuthState(status: AppAuthStatus.signedOut);
  }

  void _setState(AppAuthState nextState) {
    if (_isDisposed) {
      return;
    }
    if (_state == nextState) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
