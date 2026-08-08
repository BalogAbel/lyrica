import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';

class AppAuthController extends ChangeNotifier {
  AppAuthController(this._repository, {this._lastKnownIdentityStore})
    : _state = const AppAuthState(status: AppAuthStatus.initializing);

  final AuthRepository _repository;
  final LastKnownIdentityStore? _lastKnownIdentityStore;

  AppAuthState _state;
  StreamSubscription<AppAuthSession?>? _subscription;
  bool _isSigningOut = false;
  bool _isDisposed = false;
  int _authGeneration = 0;
  AppAuthSession? _pendingReauthCancelSession;
  int? _pendingReauthCancelGeneration;

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

  /// Cancels a different-user re-authentication: the new session is signed
  /// out at the auth backend, but -- unlike [signOut] -- this is not an
  /// explicit user sign-out. State returns to [AppAuthStatus.sessionExpired]
  /// carrying [priorSession], so the app stays offline-authenticated as the
  /// user who was signed in before the (cancelled) different-user sign-in.
  ///
  /// ADR-020 forbids destroying that prior offline-authenticated state on
  /// cancel. [_pendingReauthCancelSession] / [_pendingReauthCancelGeneration]
  /// make this convergent rather than racy across BOTH interleavings of our
  /// own [_setState] below versus the auth stream's `null` event (a side
  /// effect [_repository.signOut] may trigger, at a time this class does not
  /// control):
  ///
  /// - the stream's `null` arrives WHILE this call is still awaiting
  ///   [_repository.signOut] -- [_handleSessionUpdate] sees the pending
  ///   record, applies it, and this call's own [_setState] afterwards is a
  ///   no-op (same target state);
  /// - the stream's `null` arrives LATE, after this call has already
  ///   returned and set the state itself. The pending record is deliberately
  ///   NOT cleared in a `finally` here -- doing that would erase the record
  ///   before the late event can consume it, which is exactly how this bug
  ///   used to reach production. Instead it is left set and consumed lazily
  ///   by [_handleSessionUpdate] the next time any session event arrives,
  ///   gated on [_pendingReauthCancelGeneration] so a genuinely later,
  ///   unrelated auth event (one that bumped [_authGeneration] itself, e.g.
  ///   another sign-out or sign-in) correctly proves the record stale
  ///   instead of being wrongly reapplied.
  ///
  /// See [_handleSessionUpdate].
  Future<void> cancelReauthToPriorSession(AppAuthSession priorSession) async {
    _authGeneration += 1;
    final cancelGeneration = _authGeneration;
    _isSigningOut = true;
    _pendingReauthCancelSession = priorSession;
    _pendingReauthCancelGeneration = cancelGeneration;
    try {
      try {
        await _repository.signOut();
      } catch (error, stackTrace) {
        // Finding 2 (PR #64 review): the backend signOut() call failing
        // (offline, timeout, revoked token, ...) must not leave this cancel
        // stuck. The convergence below still has to run unconditionally --
        // both so the state does not silently stay put (still `signedIn` as
        // the would-be new user) and so the pending record above is not
        // left "live" for a later, UNRELATED null session event to
        // misapply (see the class doc): once this method itself converges
        // to sessionExpired here, a stale pending record consumed by a
        // later event lands on the exact same state and is a harmless
        // no-op via _setState's equality check, not a wrong one. Whether
        // the remote signOut() itself actually completed is a lesser
        // concern than that local convergence -- ADR-020 never requires
        // backend confirmation to stay non-destructive -- but it must not
        // vanish silently just because this is a fire-and-forget auth
        // listener; report it.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'AppAuthController',
            context: ErrorDescription(
              'cancelReauthToPriorSession: backend signOut() failed; still '
              'converging local state to sessionExpired as the prior user',
            ),
          ),
        );
      }
      // If the stream's own null event already arrived and converged on
      // this same target state while we were awaiting (see
      // _handleSessionUpdate), _authGeneration has moved past
      // cancelGeneration; skip the redundant _setState outright rather than
      // relying on its equality no-op, so this call can never clobber a
      // newer, unrelated auth event that happened to land in the same
      // window.
      if (_authGeneration == cancelGeneration) {
        _setState(
          AppAuthState(
            status: AppAuthStatus.sessionExpired,
            lastKnownSession: priorSession,
          ),
        );
      }
    } finally {
      _isSigningOut = false;
    }
  }

  void _handleSessionUpdate(AppAuthSession? session) {
    final pendingCancel = _pendingReauthCancelSession;
    final pendingGeneration = _pendingReauthCancelGeneration;
    if (pendingCancel != null) {
      // Consume the pending cancel record on whichever session event
      // arrives next, however late -- including after
      // cancelReauthToPriorSession has already returned, since its own
      // signOut() call's stream side effect is not guaranteed to be
      // delivered before the awaited future resolves. Gating on
      // _authGeneration rather than clearing this field in cancel's
      // `finally` is what lets a LATE emission still land on the
      // cancelled-to-prior-session state: nothing bumps _authGeneration
      // between the cancel and this event unless a genuinely newer auth
      // operation ran in between, in which case the record is correctly
      // treated as stale below instead of being reapplied.
      _pendingReauthCancelSession = null;
      _pendingReauthCancelGeneration = null;
      if (session == null && pendingGeneration == _authGeneration) {
        _authGeneration += 1;
        _setState(
          AppAuthState(
            status: AppAuthStatus.sessionExpired,
            lastKnownSession: pendingCancel,
          ),
        );
        return;
      }
    }
    _authGeneration += 1;
    _setState(_stateForSession(session, fromStream: true));
  }

  Future<AppAuthState> _stateForRestoredSession(AppAuthSession? session) async {
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
