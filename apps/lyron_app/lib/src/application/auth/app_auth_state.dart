import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';

class AppAuthState {
  const AppAuthState({
    required this.status,
    this.session,
    this.lastKnownSession,
  });

  final AppAuthStatus status;
  final AppAuthSession? session;
  final AppAuthSession? lastKnownSession;

  /// The user the app is acting for: the live session's user when signed
  /// in, the last known session's user when offline-authenticated
  /// (ADR-020), otherwise nobody.
  String? get currentUserId => switch (status) {
    AppAuthStatus.signedIn => session?.userId,
    AppAuthStatus.sessionExpired => lastKnownSession?.userId,
    AppAuthStatus.initializing || AppAuthStatus.signedOut => null,
  };

  @override
  bool operator ==(Object other) {
    return other is AppAuthState &&
        other.status == status &&
        _sessionEquals(other.session, session) &&
        _sessionEquals(other.lastKnownSession, lastKnownSession);
  }

  @override
  int get hashCode => Object.hash(
    status,
    session?.userId,
    session?.email,
    Object.hashAll(session?.linkedProviders ?? const <String>[]),
    lastKnownSession?.userId,
    lastKnownSession?.email,
    Object.hashAll(lastKnownSession?.linkedProviders ?? const <String>[]),
  );

  static bool _sessionEquals(AppAuthSession? left, AppAuthSession? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return left == right;
    return left.userId == right.userId &&
        left.email == right.email &&
        listEquals(left.linkedProviders, right.linkedProviders);
  }
}
