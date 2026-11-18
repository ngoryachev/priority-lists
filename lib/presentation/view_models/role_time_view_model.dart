import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/activity_event.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/role_timeline.dart';
import '../../domain/repositories/activity_log_repository.dart';
import 'node_tree_view_model.dart';

/// Today's time per role, for the thin strip along the right edge.
///
/// Read from the activity log, which every device writes to, so the strip is
/// the same everywhere. Nothing new is written for it. The log is re-read on
/// [refresh] (launch, coming back to the foreground) and every
/// [refetchEvery]; in between a [tick] moves "now" along, and a role switch
/// made on this device is counted straight away, before the log has it.
class RoleTimeViewModel extends ChangeNotifier {
  static const Duration tickEvery = Duration(minutes: 1);
  static const Duration refetchEvery = Duration(minutes: 10);

  final ActivityLogRepository _log;
  final NodeTreeViewModel _tree;
  final DateTime Function() _now;

  List<ActivityEvent> _events = const [];

  /// Switches seen on this device since the last fetch, as log-shaped events
  /// so they go through the same rules.
  final List<ActivityEvent> _local = [];

  String? _activeRoleId;
  Timer? _ticker;
  DateTime _fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  List<RoleSpan> _spans = const [];

  RoleTimeViewModel(
    this._log,
    this._tree, {
    DateTime Function()? now,
    bool startTicker = true,
  }) : _now = now ?? DateTime.now {
    _activeRoleId = _tree.activeRole?.id;
    _tree.addListener(_onTreeChanged);
    if (startTicker) {
      _ticker = Timer.periodic(tickEvery, (_) => tick());
    }
  }

  /// Today's counted spans, oldest first.
  List<RoleSpan> get spans => _spans;

  /// Start of the day the strip covers; its top edge.
  DateTime get dayStart => RoleTimeline.dayStartFor(_now());

  DateTime get now => _now();

  /// Re-reads the day's log. Failures keep what was there.
  Future<void> refresh() async {
    final now = _now();
    try {
      final events = await _log.recent(
        limit: 2000,
        since: RoleTimeline.dayStartFor(now),
      );
      if (_disposed) return;
      _events = events;
      _local.clear();
      _fetchedAt = now;
    } catch (_) {
      if (_disposed) return;
    }
    _recompute();
  }

  /// Moves "now" along, re-reading the log when it is due.
  void tick() {
    if (_now().difference(_fetchedAt) >= refetchEvery) {
      unawaited(refresh());
    } else {
      _recompute();
    }
  }

  void _onTreeChanged() {
    final roleId = _tree.activeRole?.id;
    if (roleId == _activeRoleId) return;
    final previous = _activeRoleId;
    _activeRoleId = roleId;
    // A tree that has just loaded is not a switch.
    if (previous == null || roleId == null) {
      _recompute();
      return;
    }
    final at = _now();
    _local.add(
      ActivityEvent(
        id: 'local-${at.microsecondsSinceEpoch}',
        at: at,
        action: ActivityAction.prioritized,
        nodeId: roleId,
        nodeTitle: '',
        details: '${Priority.high.label} → ${Priority.critical.label}',
      ),
    );
    _recompute();
  }

  void _recompute() {
    if (_disposed) return;
    final spans = RoleTimeline.build(
      events: [..._events, ..._local],
      now: _now(),
      currentRoleId: _activeRoleId,
    );
    // Notified even when the spans are equal: "now", the strip's bottom
    // edge, has moved.
    _spans = spans;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _tree.removeListener(_onTreeChanged);
    super.dispose();
  }
}
