import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Puts [text] on the clipboard, `false` if neither route worked.
///
/// The async clipboard API only exists on a secure origin, and it is checked
/// up front rather than tried first: awaiting a rejected promise can outlive
/// the browser's user-activation window, after which `execCommand` would be
/// refused too.
Future<bool> copyToClipboard(String text) async {
  if (_hasAsyncClipboard) {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      // Permission denied or no document focus — try the legacy route.
    }
  }
  return _copyWithExecCommand(text);
}

bool get _hasAsyncClipboard =>
    web.window.isSecureContext &&
    (web.window.navigator as JSObject).has('clipboard');

/// The pre-`navigator.clipboard` way: select text in an off-screen textarea and
/// let the browser copy the selection.
bool _copyWithExecCommand(String text) {
  final active = web.document.activeElement;
  final textarea =
      web.document.createElement('textarea') as web.HTMLTextAreaElement
        ..value = text
        ..readOnly = true
        ..setAttribute('aria-hidden', 'true')
        ..style.position = 'fixed'
        ..style.top = '0'
        ..style.left = '-9999px'
        ..style.opacity = '0';
  web.document.body!.append(textarea);
  try {
    textarea.focus();
    textarea.setSelectionRange(0, text.length);
    return web.document.execCommand('copy');
  } catch (_) {
    return false;
  } finally {
    textarea.remove();
    // Flutter's engine listens for keys on the element it focused; leaving the
    // focus on a removed textarea would swallow the keyboard.
    if (active.isA<web.HTMLElement>()) (active as web.HTMLElement).focus();
  }
}
