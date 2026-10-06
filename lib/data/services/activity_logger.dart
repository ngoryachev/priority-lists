import 'package:uuid/uuid.dart';

import '../../domain/models/activity_event.dart';
import '../../domain/models/node_tree.dart';
import '../../domain/models/priority_node.dart';
import '../../domain/repositories/activity_log_repository.dart';

/// Turns a tree mutation into a log entry.
///
/// Everything here is best-effort and fire-and-forget: callers do not await,
/// failures are swallowed, and no call may ever change the outcome of the
/// mutation it describes. Writes are chained so entries land in the order they
/// happened; [idle] waits for that chain to drain (tests, and nothing else).
class ActivityLogger {
  final ActivityLogRepository _repository;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<void> _queue = Future.value();

  ActivityLogger(
    this._repository, {
    Uuid? uuid,
    DateTime Function()? now,
  })  : _uuid = uuid ?? const Uuid(),
        _now = now ?? DateTime.now;

  /// Completes once every entry recorded so far has been written (or failed).
  Future<void> get idle => _queue;

  /// A node was added under [parentId]; [treeBefore] is the tree as it was,
  /// which is where the ancestor titles come from.
  void created(PriorityNode node, NodeTree treeBefore) {
    _record(
      action: ActivityAction.created,
      node: node,
      path: _pathUnder(treeBefore, node.parentId),
      details: node.priority.label,
    );
  }

  /// An edit through the node form or a priority button. A change that only
  /// touches the priority is logged as such — that is the move people report.
  void changed(PriorityNode before, PriorityNode after, NodeTree tree) {
    final priorityChanged = before.priority != after.priority;
    final fields = <String>[
      if (before.title != after.title) 'title "${before.title}" → "${after.title}"',
      if (before.description != after.description) 'description',
      if (before.colorPreset != after.colorPreset) 'colour',
    ];
    if (fields.isEmpty && !priorityChanged) return;

    final priorityDetail =
        '${before.priority.label} → ${after.priority.label}';
    _record(
      action: fields.isEmpty ? ActivityAction.prioritized : ActivityAction.updated,
      node: after,
      path: _pathUnder(tree, after.parentId),
      details: [
        if (priorityChanged) priorityDetail,
        ...fields,
      ].join(', '),
    );
  }

  /// A node (and its subtree) was removed. [treeBefore] still contains it.
  void deleted(PriorityNode node, NodeTree treeBefore) {
    final nested = treeBefore.descendantCount(node.id);
    _record(
      action: ActivityAction.deleted,
      node: node,
      path: _pathUnder(treeBefore, node.parentId),
      details: nested == 0 ? '' : 'with $nested nested',
    );
  }

  /// A node was re-parented. Both paths are read from [treeBefore], which still
  /// has the node in its old place.
  void moved(PriorityNode node, NodeTree treeBefore, String? newParentId) {
    _record(
      action: ActivityAction.moved,
      node: node,
      path: _pathUnder(treeBefore, newParentId),
      details: '${_place(treeBefore, node.parentId)} → '
          '${_place(treeBefore, newParentId)}',
    );
  }

  /// A node was dragged to another rank among its siblings. Only the dragged
  /// node is logged: the siblings that shifted along are noise.
  void reordered(PriorityNode before, PriorityNode after, NodeTree treeBefore) {
    final moves = <String>[
      if (before.position != after.position)
        'rank ${before.position + 1} → ${after.position + 1}',
      if (before.priority != after.priority)
        '${before.priority.label} → ${after.priority.label}',
    ];
    if (moves.isEmpty) return;
    _record(
      action: ActivityAction.reordered,
      node: after,
      path: _pathUnder(treeBefore, after.parentId),
      details: moves.join(', '),
    );
  }

  /// Where a node sits, for the before/after of a move.
  String _place(NodeTree tree, String? parentId) {
    if (parentId == null) return 'top level';
    final path = tree.pathTo(parentId).map((n) => n.title).toList();
    return path.isEmpty ? 'top level' : path.join(' › ');
  }

  List<String> _pathUnder(NodeTree tree, String? parentId) =>
      [for (final ancestor in tree.pathTo(parentId)) ancestor.title];

  void _record({
    required ActivityAction action,
    required PriorityNode node,
    required List<String> path,
    required String details,
  }) {
    final event = ActivityEvent(
      id: _uuid.v4(),
      at: _now(),
      action: action,
      nodeId: node.id,
      nodeTitle: node.title,
      path: path,
      details: details,
    );
    _queue = _queue.then((_) => _repository.append(event)).catchError((_) {
      // A log that cannot be written must never surface as a failed mutation.
    });
  }
}
