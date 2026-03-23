import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_status.dart';

class AppAuthState {
  const AppAuthState({required this.status, this.session});

  final AppAuthStatus status;
  final AppAuthSession? session;
}
