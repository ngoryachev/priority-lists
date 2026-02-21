import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_item.dart';
import 'package:priority_lists/domain/models/priority_list.dart';
import 'package:priority_lists/domain/repositories/priority_list_repository.dart';
import 'package:priority_lists/presentation/view_models/list_detail_view_model.dart';

class MockRepository extends Mock implements PriorityListRepository {}

void main() {
  late MockRepository mockRepository;
  final now = DateTime(2024, 1, 1);

  PriorityList makeList({List<PriorityItem>? items}) {
    return PriorityList(
      id: 'list-1',
      name: 'Test',
      colorPreset: ColorPreset.blue,
      items: items,
      createdAt: now,
      updatedAt: now,
    );
  }

  PriorityItem makeItem(String id, Priority priority) {
    return PriorityItem(
      id: id,
      title: 'Item $id',
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() {
    mockRepository = MockRepository();
    registerFallbackValue(makeList());
  });

  group('ListDetailViewModel', () {
    test('addItem adds item and saves', () async {
      when(() => mockRepository.saveList(any())).thenAnswer((_) async {});
      final vm = ListDetailViewModel(mockRepository, makeList());

      await vm.addItem('New Task', 'Description', Priority.high);

      expect(vm.list.items, hasLength(1));
      expect(vm.list.items.first.title, 'New Task');
      expect(vm.list.items.first.priority, Priority.high);
      verify(() => mockRepository.saveList(any())).called(1);
    });

    test('updateItem modifies item and saves', () async {
      when(() => mockRepository.saveList(any())).thenAnswer((_) async {});
      final item = makeItem('i1', Priority.low);
      final vm = ListDetailViewModel(mockRepository, makeList(items: [item]));

      final updated = item.copyWith(title: 'Updated', priority: Priority.critical);
      await vm.updateItem(updated);

      expect(vm.list.items.first.title, 'Updated');
      expect(vm.list.items.first.priority, Priority.critical);
      verify(() => mockRepository.saveList(any())).called(1);
    });

    test('deleteItem removes item and saves', () async {
      when(() => mockRepository.saveList(any())).thenAnswer((_) async {});
      final item = makeItem('i1', Priority.high);
      final vm = ListDetailViewModel(mockRepository, makeList(items: [item]));

      await vm.deleteItem('i1');

      expect(vm.list.items, isEmpty);
      verify(() => mockRepository.saveList(any())).called(1);
    });

    test('sortedItems returns items sorted by priority', () async {
      when(() => mockRepository.saveList(any())).thenAnswer((_) async {});
      final vm = ListDetailViewModel(mockRepository, makeList(items: [
        makeItem('low', Priority.low),
        makeItem('critical', Priority.critical),
        makeItem('medium', Priority.medium),
      ]));

      final sorted = vm.sortedItems;
      expect(sorted[0].id, 'critical');
      expect(sorted[1].id, 'medium');
      expect(sorted[2].id, 'low');
    });

    test('updateListDetails changes name and color', () async {
      when(() => mockRepository.saveList(any())).thenAnswer((_) async {});
      final vm = ListDetailViewModel(mockRepository, makeList());

      await vm.updateListDetails('New Name', ColorPreset.red);

      expect(vm.list.name, 'New Name');
      expect(vm.list.colorPreset, ColorPreset.red);
    });
  });
}
