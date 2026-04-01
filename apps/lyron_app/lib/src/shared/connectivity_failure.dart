import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

bool isConnectivityFailure(Object error) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException ||
      error is AuthRetryableFetchException) {
    return true;
  }

  if (error is PostgrestException) {
    if (_isRetryableHttpStatus(error.code)) {
      return true;
    }

    final details = [
      error.message,
      error.details,
      error.hint,
    ].whereType<String>().join(' ').toLowerCase();
    if (_containsConnectivitySignal(details)) {
      return true;
    }
  }

  final runtimeType = error.runtimeType.toString();
  if (runtimeType == 'ClientException') {
    return true;
  }

  return _containsConnectivitySignal(error.toString().toLowerCase());
}

bool _isRetryableHttpStatus(String? code) {
  switch (code) {
    case '502':
    case '503':
    case '504':
      return true;
    default:
      return false;
  }
}

bool _containsConnectivitySignal(String message) {
  return message.contains('clientexception') ||
      message.contains('connection closed') ||
      message.contains('connection refused') ||
      message.contains('connection reset') ||
      message.contains('connection timed out') ||
      message.contains('failed host lookup') ||
      message.contains('network is unreachable') ||
      message.contains('no address associated with hostname') ||
      message.contains('service unavailable') ||
      message.contains('socketexception') ||
      message.contains('timed out') ||
      message.contains('upstream connect error');
}
