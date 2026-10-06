import '../../domain/models/activity_event.dart';
import '../../domain/repositories/activity_log_repository.dart';

/// Log storage for platforms without file access (web) and for tests.
/// Lives only as long as the process does.
class InMemoryActivityLogRepository implements ActivityLogRepository {
  final List<ActivityEvent> _events = [];

  @override
  Future<void> append(ActivityEvent event) async => _events.add(event);

  @override
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since}) async {
    final matching = _events
        .where((event) => since == null || !event.at.isBefore(since))
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return matching.take(limit).toList();
  }
}
