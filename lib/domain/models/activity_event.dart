/// What a logged mutation did to a node.
///
/// [updated] covers edits of title/description/colour; a priority change gets
/// its own kind because it is the most frequent deliberate act in this app and
/// the one worth reading back on a standup.
enum ActivityAction {
  created('Added'),
  updated('Edited'),
  prioritized('Re-prioritised'),
  moved('Moved'),
  reordered('Reordered'),
  deleted('Deleted');

  const ActivityAction(this.label);

  /// How the action is named wherever it is read: the tooltip on a log row and
  /// the line of a copied daily digest.
  final String label;

  static ActivityAction fromName(String name) => ActivityAction.values
      .firstWhere((a) => a.name == name, orElse: () => ActivityAction.updated);
}

/// One recorded mutation, kept forever even after the node it talks about is
/// gone — hence the snapshotted [nodeTitle] and [path] instead of a lookup.
class ActivityEvent {
  final String id;
  final DateTime at;
  final ActivityAction action;

  /// The node the mutation touched. Null is never written by the app, but the
  /// field stays nullable so a log row survives a node id it cannot parse.
  final String? nodeId;

  final String nodeTitle;

  /// Ancestor titles at the time of the mutation, root first, excluding the
  /// node itself. Empty for a top-level node.
  final List<String> path;

  /// Human-readable specifics: `Medium → High`, `Root → Work`, and so on.
  final String details;

  ActivityEvent({
    required this.id,
    required this.at,
    required this.action,
    required this.nodeId,
    required this.nodeTitle,
    List<String> path = const [],
    this.details = '',
  }) : path = List.unmodifiable(path);

  /// The day the event belongs to, as a date with no time component — the key
  /// the log groups by.
  DateTime get day => DateTime(at.year, at.month, at.day);

  String get pathLabel => path.join(' › ');

  /// One line as pasted into a standup note, where the location matters as
  /// much as what happened.
  String get digestLine {
    final where = path.isEmpty ? '' : ' (in $pathLabel)';
    final what = details.isEmpty ? '' : ' — $details';
    return '${action.label}: "$nodeTitle"$where$what';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ActivityEvent && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Every event of one calendar day, newest first.
class ActivityDay {
  final DateTime day;
  final List<ActivityEvent> events;

  ActivityDay(this.day, List<ActivityEvent> events)
      : events = List.unmodifiable(events);

  /// Splits a flat event list into days, newest day first and newest event
  /// first inside each day. The input may come in any order.
  static List<ActivityDay> group(Iterable<ActivityEvent> events) {
    final byDay = <DateTime, List<ActivityEvent>>{};
    for (final event in events) {
      byDay.putIfAbsent(event.day, () => []).add(event);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        ActivityDay(day, byDay[day]!..sort((a, b) => b.at.compareTo(a.at))),
    ];
  }

  /// Plain-text recap of the day, ready to paste into a standup.
  ///
  /// Events are retold oldest first — a standup is told forwards — and grouped
  /// by action so "added five things, deleted one" reads at a glance.
  String digest() {
    final buffer = StringBuffer('${formatDay(day)} — ${_countLabel()}')
      ..writeln();
    for (final action in ActivityAction.values) {
      final ofAction = events.where((e) => e.action == action).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      for (final event in ofAction) {
        buffer.writeln('- ${event.digestLine}');
      }
    }
    return buffer.toString().trimRight();
  }

  String _countLabel() =>
      '${events.length} change${events.length == 1 ? '' : 's'}';

  static String formatDay(DateTime day) =>
      '${day.year}-${_two(day.month)}-${_two(day.day)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
