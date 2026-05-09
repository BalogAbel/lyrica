// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

class BrowserUnsavedChangesGuard {
  const BrowserUnsavedChangesGuard._();

  static bool _enabled = false;

  static void setEnabled(bool enabled) {
    if (_enabled == enabled) {
      return;
    }

    _enabled = enabled;
    if (enabled) {
      html.window.addEventListener('beforeunload', _handleBeforeUnload);
    } else {
      html.window.removeEventListener('beforeunload', _handleBeforeUnload);
    }
  }

  static void _handleBeforeUnload(html.Event event) {
    event.preventDefault();
    if (event is html.BeforeUnloadEvent) {
      event.returnValue = '';
    }
  }
}
