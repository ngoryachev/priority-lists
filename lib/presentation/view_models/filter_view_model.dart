import 'package:flutter/foundation.dart';

import '../../domain/models/priority.dart';

/// Global priority-visibility filter shared across screens.
///
/// [level] selects the lowest [Priority.value] that is still visible:
///   * 1 — only `critical`
///   * 2 — `critical` + `high`
///   * 3 — `critical` + `high` + `medium`
///   * 4 — every priority (default)
class FilterViewModel extends ChangeNotifier {
  static const int minLevel = 1;
  static const int maxLevel = 4;

  int _level = maxLevel;

  int get level => _level;

  void setLevel(int level) {
    if (level < minLevel || level > maxLevel) return;
    if (level == _level) return;
    _level = level;
    notifyListeners();
  }

  bool isVisible(Priority priority) => priority.value <= _level;
}
