import '../models/activity_event.dart';

/// Append-only history of tree mutations.
///
/// Deliberately separate from `PriorityNodeRepository`: the log is a side
/// record, it never participates in a write that changes the tree, and losing
/// it must never fail a mutation.
abstract class ActivityLogRepository {
  /// Records one event. Implementations should be cheap; callers do not await
  /// this on the UI path.
  Future<void> append(ActivityEvent event);

  /// Events newest first, at most [limit] of them, optionally only those at or
  /// after [since].
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since});
}
