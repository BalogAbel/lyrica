// apps/lyron_app/lib/src/application/auth/deep_link_listener.dart
import 'dart:async';

import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';

class DeepLinkListener {
  DeepLinkListener({
    required this._stream,
    required this._pendingTokens,
  });

  final Stream<Uri> _stream;
  final PendingInviteTokenController _pendingTokens;
  StreamSubscription<Uri>? _sub;

  void start() {
    _sub ??= _stream.listen(_handle);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _handle(Uri uri) {
    final isHttpInvite = uri.path == '/invite' || uri.path == '/invite/';
    final isCustomSchemeCallback =
        uri.scheme == 'io.lyron.app' && uri.host == 'auth';
    if (isHttpInvite || isCustomSchemeCallback) {
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        _pendingTokens.capture(token);
      }
    }
  }
}
