import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_last_node_repository.dart';
import 'package:priority_lists/domain/models/node_tree.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/last_node_repository.dart';
import 'package:priority_lists/presentation/view_models/last_node_view_model.dart';

PriorityNode node(String id, {String? parent}) {
  final created = DateTime(2026, 1, 1);
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    description: '',
    priority: Priority.medium,
    createdAt: created,
    updatedAt: created,
  );
}

/// A > B > C, plus a second root.
final tree = NodeTree([
  node('A'),
  node('B', parent: 'A'),
  node('C', parent: 'B'),
  node('Other'),
]);

/// Records the order of calls, so the chained queue can be checked.
class _RecordingRepository implements LastNodeRepository {
  final calls = <String>[];
  LastNodePointer? stored;

  @override
  Future<LastNodePointer?> load() async => stored;

  @override
  Future<void> save(LastNodePointer pointer) async {
    calls.add(pointer.nodeId ?? 'root');
    stored = pointer;
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    stored = null;
  }
}

/// Every call fails: a broken settings store must mean "open at the root",
/// never an error over the tree.
class _BrokenRepository implements LastNodeRepository {
  @override
  Future<LastNodePointer?> load() async => throw StateError('no storage');

  @override
  Future<void> save(LastNodePointer pointer) async =>
      throw StateError('no storage');

  @override
  Future<void> clear() async => throw StateError('no storage');
}

LastNodeViewModel viewModel(
  LastNodeRepository? repository, {
  String? userId = 'user-1',
}) {
  return LastNodeViewModel(
    repository: repository,
    currentUserId: () => userId,
  );
}

void main() {
  group('resolveRestorePath', () {
    test('rebuilds the whole root-to-node path', () async {
      final vm = viewModel(
        InMemoryLastNodeRepository(
          const LastNodePointer(userId: 'user-1', nodeId: 'C'),
        ),
      );

      final path = await vm.resolveRestorePath(tree);

      expect(path.map((n) => n.id), ['A', 'B', 'C']);
    });

    test('a root pointer stays at the root', () async {
      final repository = InMemoryLastNodeRepository(
        const LastNodePointer(userId: 'user-1'),
      );
      final vm = viewModel(repository);

      expect(await vm.resolveRestorePath(tree), isEmpty);
      // Still a perfectly good pointer: nothing to forget.
      expect(await repository.load(), isNotNull);
    });

    test('nothing stored stays at the root', () async {
      expect(
        await viewModel(InMemoryLastNodeRepository()).resolveRestorePath(tree),
        isEmpty,
      );
    });

    test('no settings store at all stays at the root', () async {
      expect(await viewModel(null).resolveRestorePath(tree), isEmpty);
    });

    test('a pointer from another account is ignored and cleared', () async {
      final repository = _RecordingRepository()
        ..stored = const LastNodePointer(userId: 'somebody-else', nodeId: 'C');
      final vm = viewModel(repository);

      expect(await vm.resolveRestorePath(tree), isEmpty);
      await vm.idle;
      expect(repository.stored, isNull);
      expect(repository.calls, ['clear']);
    });

    test('a node that is no longer in the tree is cleared', () async {
      final repository = _RecordingRepository()
        ..stored = const LastNodePointer(userId: 'user-1', nodeId: 'deleted');
      final vm = viewModel(repository);

      expect(await vm.resolveRestorePath(tree), isEmpty);
      await vm.idle;
      expect(repository.stored, isNull);
    });

    /// `NodeTree` treats a node whose parent is missing as a root, so an
    /// orphan is still reachable — and still worth reopening.
    test('an orphan resolves to its own single-node path', () async {
      final orphaned = NodeTree([node('Stray', parent: 'gone')]);
      final vm = viewModel(
        InMemoryLastNodeRepository(
          const LastNodePointer(userId: 'user-1', nodeId: 'Stray'),
        ),
      );

      expect(
        (await vm.resolveRestorePath(orphaned)).map((n) => n.id),
        ['Stray'],
      );
    });

    /// A sign-out can land between the root screen mounting and this read
    /// resolving. That is not somebody else's pointer, and wiping it would
    /// cost the user a restore for no reason — `remember` is equally quiet
    /// when there is no user id.
    test('keeps the pointer when nobody is signed in', () async {
      final repository = _RecordingRepository()
        ..stored = const LastNodePointer(userId: 'user-1', nodeId: 'C');
      final vm = viewModel(repository, userId: null);

      expect(await vm.resolveRestorePath(tree), isEmpty);
      await vm.idle;
      expect(repository.stored, isNotNull);
      expect(repository.calls, isEmpty);
    });

    test('a store that throws stays at the root without raising', () async {
      expect(await viewModel(_BrokenRepository()).resolveRestorePath(tree),
          isEmpty);
    });

    /// The read must not cross an in-flight write, or it hands back the level
    /// the user just left.
    test('reads behind a pending write, not across it', () async {
      final repository = _RecordingRepository()
        ..stored = const LastNodePointer(userId: 'user-1', nodeId: 'A');
      final vm = viewModel(repository);

      vm.remember('C');
      final path = await vm.resolveRestorePath(tree);

      expect(path.map((n) => n.id), ['A', 'B', 'C']);
    });
  });

  group('remember', () {
    test('writes land in call order', () async {
      final repository = _RecordingRepository();
      final vm = viewModel(repository);

      vm.remember('A');
      vm.remember('B');
      vm.remember('C');
      vm.remember(null);
      await vm.idle;

      expect(repository.calls, ['A', 'B', 'C', 'root']);
      expect(repository.stored, const LastNodePointer(userId: 'user-1'));
    });

    test('stamps the pointer with the signed-in user', () async {
      final repository = _RecordingRepository();
      viewModel(repository, userId: 'user-9').remember('C');
      await Future<void>.delayed(Duration.zero);

      expect(
        repository.stored,
        const LastNodePointer(userId: 'user-9', nodeId: 'C'),
      );
    });

    /// A pointer without an account could never pass the account check, so
    /// there is nothing to gain from writing one.
    test('writes nothing while nobody is signed in', () async {
      final repository = _RecordingRepository();
      final vm = viewModel(repository, userId: null);

      vm.remember('C');
      await vm.idle;

      expect(repository.calls, isEmpty);
      expect(repository.stored, isNull);
    });

    test('a failing write never surfaces', () async {
      final vm = viewModel(_BrokenRepository());
      vm.remember('C');
      await expectLater(vm.idle, completes);
    });

    test('is a no-op without a settings store', () async {
      final vm = viewModel(null);
      vm.remember('C');
      await expectLater(vm.idle, completes);
    });
  });
}
