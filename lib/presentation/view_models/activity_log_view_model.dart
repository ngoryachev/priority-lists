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

  /// Event ids the user ticked for the next copy. Empty means "no selection",
  /// which the screen reads as "copy everything" — not as "copy nothing".
  final Set<String> _selectedIds = {};

  ActivityLogViewModel(this._repository);

  List<ActivityDay> get days => _days;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get windowDays => _windowDays;

  bool get hasSelection => _selectedIds.isNotEmpty;
  int get selectedCount => _selectedIds.length;

  bool isSelected(String eventId) => _selectedIds.contains(eventId);

  /// The ticked events of one day, in the day's own order (newest first).
  List<ActivityEvent> selectedIn(ActivityDay day) =>
      day.events.where((e) => _selectedIds.contains(e.id)).toList();

  void setEventSelected(String eventId, bool selected) {
    if (selected ? _selectedIds.add(eventId) : _selectedIds.remove(eventId)) {
      notifyListeners();
    }
  }

  /// Ticks or unticks every row of [day] — what the day header's checkbox does.
  void setDaySelected(ActivityDay day, bool selected) {
    final ids = day.events.map((e) => e.id);
    if (selected) {
      _selectedIds.addAll(ids);
    } else {
      _selectedIds.removeAll(ids);
    }
    notifyListeners();
  }

  Future<void> load({int? windowDays}) async {
    if (windowDays != null) _windowDays = windowDays;
    _isLoading = true;
    _error = null;
    // A reload or a new period shows a different set of rows, so whatever was
    // ticked no longer means what the user ticked it for.
    _selectedIds.clear();
    notifyListeners();

    try {
      // Counted in calendar days including today, so "Today" means from this
      // morning and "Last 7 days" covers this day and the six before it.
      final today = DateTime.now();
      final since = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: _windowDays - 1));
      _days = ActivityDay.group(await _repository.recent(since: since));
      _pruneSelection();
    } catch (e) {
      _error = e.toString();
      _days = [];
      _selectedIds.clear();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Forgets ticks for events the loaded log no longer holds. The list stays
  /// on screen and tickable while a reload is in flight, so a row ticked
  /// during it can be missing from the log that arrives.
  void _pruneSelection() {
    if (_selectedIds.isEmpty) return;
    final present = {
      for (final day in _days)
        for (final event in day.events) event.id,
    };
    _selectedIds.retainWhere(present.contains);
  }
}
