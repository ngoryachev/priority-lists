import 'package:flutter/foundation.dart';

class FilterViewModel extends ChangeNotifier {
  bool _hideLow = false;

  bool get hideLow => _hideLow;

  void toggleHideLow() {
    _hideLow = !_hideLow;
    notifyListeners();
  }
}
