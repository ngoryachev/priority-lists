import 'package:flutter/foundation.dart';

import '../../domain/models/activity_event.dart';
import '../../domain/repositories/activity_log_repository.dart';

/// Backs the history screen: loads the log and hands it over grouped by day.
class ActivityLogViewModel extends ChangeNotifier {
  /// How far back the screen looks by default. A standup is about the last day
  /// or two; a fortnight covers "what did I do since the last one".
  static const int defaultDays = 14;

  final ActivityLogRepository _repository;

  List<ActivityDay> _days = [];
  bool _isLoading = false;
  String? _error;
  int _windowDays = defaultDays;

  ActivityLogViewModel(this._repository);

  List<ActivityDay> get days => _days;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get windowDays => _windowDays;

  Future<void> load({int? windowDays}) async {
    if (windowDays != null) _windowDays = windowDays;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Counted in calendar days including today, so "Today" means from this
      // morning and "Last 7 days" covers this day and the six before it.
      final today = DateTime.now();
      final since = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: _windowDays - 1));
      _days = ActivityDay.group(await _repository.recent(since: since));
    } catch (e) {
      _error = e.toString();
      _days = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
