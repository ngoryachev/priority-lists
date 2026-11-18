import 'activity_event.dart';
import 'priority.dart';

/// A stretch of the day counted towards one role.
class RoleSpan {
  final String roleId;
  final DateTime start;
  final DateTime end;

  const RoleSpan(this.roleId, this.start, this.end);

  Duration get duration => end.difference(start);

  @override
  bool operator ==(Object other) =>
      other is RoleSpan &&
      other.roleId == roleId &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(roleId, start, end);

  @override
  String toString() => 'RoleSpan($roleId, $start – $end)';
}

/// Which role the user spent today in, worked out from the activity log alone.
///
/// The rules, as agreed with the user:
/// * The day starts at [dayStartHour]; before that the previous day is still
///   running. Nothing is counted until the first logged action of the day.
/// * During the day the app may be closed: the time keeps going to the role
///   that was active last.
/// * From [eveningHour] on, [idleCutoff] without any logged action stops the
///   count at the moment the evening stretch went quiet (the last action, or
///   [eveningHour] itself if that came earlier). The next action resumes it.
/// * A role switch is a top-level node becoming `critical`; the role it took
///   the slot from is logged as going from `critical` to something lower.
class RoleTimeline {
  static const int dayStartHour = 6;
  static const int eveningHour = 20;
  static const Duration idleCutoff = Duration(hours: 2);

  /// Start of the day [now] belongs to.
  static DateTime dayStartFor(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, dayStartHour);
    return now.isBefore(today)
        ? DateTime(now.year, now.month, now.day - 1, dayStartHour)
        : today;
  }

  /// Spans of the day [now] belongs to, oldest first.
  ///
  /// [events] may come in any order and may reach before the day start; only
  /// the day's own are used. [currentRoleId] is the active role now — what
  /// the whole day counts towards when it had no switch.
  static List<RoleSpan> build({
    required Iterable<ActivityEvent> events,
    required DateTime now,
    required String? currentRoleId,
  }) {
    final dayStart = dayStartFor(now);
    final evening = DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      eveningHour,
    );
    final day =
        events
            .where((e) => !e.at.isBefore(dayStart) && !e.at.isAfter(now))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    if (day.isEmpty) return const [];

    final switches = <(DateTime, String)>[];
    ActivityEvent? firstDeactivation;
    for (final event in day) {
      switch (_roleChange(event)) {
        case _Change.activated:
          switches.add((event.at, event.nodeId!));
        case _Change.deactivated:
          firstDeactivation ??= event;
        case null:
          break;
      }
    }
    // The role active before the day's first switch: the one that lost the
    // red slot in it (logged next to the activation, in either order), or —
    // no switch at all — the current one. A first switch with no such entry
    // leaves the time before it unattributed.
    final String? initialRole;
    if (switches.isEmpty) {
      initialRole = firstDeactivation?.nodeId ?? currentRoleId;
    } else if (firstDeactivation != null &&
        !firstDeactivation.at.isAfter(
          switches.first.$1.add(const Duration(minutes: 1)),
        )) {
      initialRole = firstDeactivation.nodeId;
    } else {
      initialRole = null;
    }

    // Counted stretches.
    final counted = <(DateTime, DateTime)>[];
    var from = day.first.at;
    var last = day.first.at;
    for (final event in day.skip(1)) {
      final quietFrom = last.isAfter(evening) ? last : evening;
      if (event.at.difference(quietFrom) >= idleCutoff) {
        counted.add((from, quietFrom.isAfter(from) ? quietFrom : from));
        from = event.at;
      }
      last = event.at;
    }
    final quietFrom = last.isAfter(evening) ? last : evening;
    final end = now.difference(quietFrom) >= idleCutoff
        ? (quietFrom.isAfter(from) ? quietFrom : from)
        : now;
    counted.add((from, end));

    // Cut the counted stretches at every switch.
    final spans = <RoleSpan>[];
    for (final (start, stop) in counted) {
      if (!stop.isAfter(start)) continue;
      var cursor = start;
      String? role = _roleAt(start, initialRole, switches);
      for (final (at, roleId) in switches) {
        if (!at.isAfter(cursor) || !at.isBefore(stop)) continue;
        if (role != null) spans.add(RoleSpan(role, cursor, at));
        cursor = at;
        role = roleId;
      }
      if (role != null) spans.add(RoleSpan(role, cursor, stop));
    }
    return spans;
  }

  static String? _roleAt(
    DateTime at,
    String? initialRole,
    List<(DateTime, String)> switches,
  ) {
    var role = initialRole;
    for (final (switchAt, roleId) in switches) {
      if (switchAt.isAfter(at)) break;
      role = roleId;
    }
    return role;
  }

  static final _critical = Priority.critical.label;

  /// Whether [event] made a role active or took it out of the red slot.
  static _Change? _roleChange(ActivityEvent event) {
    if (event.path.isNotEmpty || event.nodeId == null) return null;
    if (event.action == ActivityAction.created) {
      return event.details == _critical ? _Change.activated : null;
    }
    for (final clause in event.details.split(',')) {
      final parts = clause.trim().split(' → ');
      if (parts.length != 2) continue;
      if (parts[1] == _critical && parts[0] != _critical) {
        return _Change.activated;
      }
      if (parts[0] == _critical && parts[1] != _critical) {
        return _Change.deactivated;
      }
    }
    return null;
  }
}

enum _Change { activated, deactivated }
