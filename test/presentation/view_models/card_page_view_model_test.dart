import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/presentation/view_models/card_page_view_model.dart';

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
}
