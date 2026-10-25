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

/// The pre-`navigator.clipboard` way: select the text in a textarea nobody can
/// see and let the browser copy the selection.
///
/// Everything happens inside the `try`, down to creating the element: a copy
/// that cannot be made has to come back as `false` so the caller can offer the
/// text to copy by hand, never as a throw out of [copyToClipboard].
bool _copyWithExecCommand(String text) {
  final active = web.document.activeElement;
  web.HTMLTextAreaElement? textarea;
  try {
    textarea = web.document.createElement('textarea') as web.HTMLTextAreaElement
      ..value = text
      // Editable and not read-only: mobile Safari refuses to copy out of a
      // read-only field. It also wants the element inside the viewport, hence
      // a 1px corner at zero rather than the usual left: -9999px.
      ..contentEditable = 'true'
      ..setAttribute('aria-hidden', 'true')
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '1px'
      ..style.height = '1px'
      ..style.opacity = '0'
      // Safari zooms the page when it focuses anything smaller than this.
      ..style.fontSize = '16px';
    web.document.body!.append(textarea);

    textarea.focus();
    textarea.setSelectionRange(0, text.length);
    // What iOS actually reads: the document selection, not the field's own.
    final selection = web.window.getSelection();
    if (selection != null) {
      final range = web.document.createRange()..selectNodeContents(textarea);
      selection
        ..removeAllRanges()
        ..addRange(range);
    }
    return web.document.execCommand('copy');
  } catch (_) {
    return false;
  } finally {
    textarea?.remove();
    // Flutter's engine listens for keys on the element it focused; leaving the
    // focus on a removed textarea would swallow the keyboard.
    if (active.isA<web.HTMLElement>()) (active as web.HTMLElement).focus();
  }
}
