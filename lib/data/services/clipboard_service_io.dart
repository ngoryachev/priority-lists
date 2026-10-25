import 'package:flutter/services.dart';

/// Puts [text] on the clipboard, `false` if the platform refused.
Future<bool> copyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}
