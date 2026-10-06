import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_activity_log_repository.dart';
import 'package:priority_lists/domain/models/activity_event.dart';

ActivityEvent event(String id, DateTime at) => ActivityEvent(
      id: id,
      at: at,
      action: ActivityAction.created,
      nodeId: 'n-$id',
      nodeTitle: 'Node $id',
    );

void main() {
  late InMemoryActivityLogRepository repository;

  setUp(() => repository = InMemoryActivityLogRepository());

  Future<void> seed(List<ActivityEvent> events) async {
    for (final e in events) {
      await repository.append(e);
    }
  }

  test('reads back newest first whatever order it was written in', () async {
    await seed([
      event('b', DateTime(2026, 10, 6, 9)),
      event('c', DateTime(2026, 10, 7, 9)),
      event('a', DateTime(2026, 10, 5, 9)),
    ]);

    expect((await repository.recent()).map((e) => e.id), ['c', 'b', 'a']);
  });

  test('a limit keeps the newest entries, not the first written', () async {
    await seed([
      event('old', DateTime(2026, 10, 1)),
      event('mid', DateTime(2026, 10, 2)),
      event('new', DateTime(2026, 10, 3)),
    ]);

    expect((await repository.recent(limit: 2)).map((e) => e.id),
        ['new', 'mid']);
  });

  test('since is inclusive of an entry landing exactly on the boundary',
      () async {
    final boundary = DateTime(2026, 10, 6);
    await seed([
      event('before', boundary.subtract(const Duration(milliseconds: 1))),
      event('on', boundary),
      event('after', boundary.add(const Duration(hours: 1))),
    ]);

    expect((await repository.recent(since: boundary)).map((e) => e.id),
        ['after', 'on']);
  });

  test('an empty log reads as an empty list', () async {
    expect(await repository.recent(), isEmpty);
  });
}
