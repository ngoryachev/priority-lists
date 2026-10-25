/// Copying text to the system clipboard, with a web-only escape hatch.
///
/// The app is also served over plain HTTP (`http://65.21.0.66:8000/`), an
/// insecure origin where `navigator.clipboard` does not exist and Flutter's
/// `Clipboard.setData` therefore fails. The web implementation falls back to a
/// hidden textarea plus `document.execCommand('copy')`; everywhere else the
/// platform channel is all there is. Both report whether the text actually
/// made it, so callers can say "copied" only when it is true.
library;

export 'clipboard_service_io.dart'
    if (dart.library.js_interop) 'clipboard_service_web.dart';
