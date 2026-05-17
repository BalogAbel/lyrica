import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';

class AppAuthState {
  const AppAuthState({required this.status, this.session});

  final AppAuthStatus status;
  final AppAuthSession? session;

  @override
  bool operator ==(Object other) {
    return other is AppAuthState &&
        other.status == status &&
        _sessionEquals(other.session, session);
  }

  @override
  int get hashCode => Object.hash(
    status,
    session?.userId,
    session?.email,
    Object.hashAll(session?.linkedProviders ?? const <String>[]),
  );

  static bool _sessionEquals(AppAuthSession? left, AppAuthSession? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return left == right;
    return left.userId == right.userId &&
        left.email == right.email &&
        listEquals(left.linkedProviders, right.linkedProviders);
  }
}
