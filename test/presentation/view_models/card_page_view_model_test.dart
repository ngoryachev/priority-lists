import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/repositories/card_page_repository.dart';
import 'package:priority_lists/presentation/view_models/card_page_view_model.dart';

class _Store implements CardPageRepository {
  Map<String, String>? stored;
  final saves = <Map<String, String>>[];
  bool failing = false;

  @override
  Future<Map<String, String>?> load() async {
    if (failing) throw StateError('offline');
    return stored == null ? null : Map.of(stored!);
  }

  @override
  Future<void> save(Map<String, String> pages) async {
    if (failing) throw StateError('offline');
    saves.add(pages);
    stored = Map.of(pages);
  }
}

void main() {
  group('CardPageViewModel', () {
    test('a node with nothing recorded sits on page 0', () {
      expect(CardPageViewModel().childFor('a'), isNull);
    });

    test('remembers one child per node', () {
      final pages = CardPageViewModel()
        ..remember('a', 'a1')
        ..remember('b', 'b1');

      expect(pages.childFor('a'), 'a1');
      expect(pages.childFor('b'), 'b1');
    });

    test('a later page replaces the earlier one', () {
      final pages = CardPageViewModel()
        ..remember('a', 'a1')
        ..remember('a', 'a2');

      expect(pages.childFor('a'), 'a2');
    });

    test('null forgets the page, which is a swipe back to the node itself',
        () {
      final pages = CardPageViewModel()..remember('a', 'a1');
      pages.remember('a', null);

      expect(pages.childFor('a'), isNull);
    });
  });

  group('CardPageViewModel with a store', () {
    test('every change writes the whole map, in order', () async {
      final store = _Store();
      final pages = CardPageViewModel(repository: store)
        ..remember('a', 'a1')
        ..remember('b', 'b1')
        ..remember('a', null);
      await pages.idle;

      expect(store.saves, [
        {'a': 'a1'},
        {'a': 'a1', 'b': 'b1'},
        {'b': 'b1'},
      ]);
    });

    test('remembering the page a card is already on writes nothing', () async {
      final store = _Store();
      final pages = CardPageViewModel(repository: store)..remember('a', null);
      await pages.idle;

      expect(store.saves, isEmpty);
    });

    test('reload takes the stored pages and bumps the revision', () async {
      final store = _Store()..stored = {'a': 'a2'};
      final pages = CardPageViewModel(repository: store)..remember('b', 'b1');
      await pages.idle;
      store.stored = {'a': 'a2'};

      await pages.reload();

      expect(pages.childFor('a'), 'a2');
      expect(pages.childFor('b'), isNull);
      expect(pages.revision.value, 1);
    });

    test('reload with nothing new keeps the revision', () async {
      final store = _Store();
      final pages = CardPageViewModel(repository: store)..remember('a', 'a1');
      await pages.reload();

      expect(pages.childFor('a'), 'a1');
      expect(pages.revision.value, 0);
    });

    test('a store that fails keeps the pages in memory', () async {
      final store = _Store()..failing = true;
      final pages = CardPageViewModel(repository: store)..remember('a', 'a1');
      await pages.idle;
      await pages.reload();

      expect(pages.childFor('a'), 'a1');
    });
  });
}
