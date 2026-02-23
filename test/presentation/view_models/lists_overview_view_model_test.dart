import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_list.dart';
import 'package:priority_lists/domain/repositories/priority_list_repository.dart';
import 'package:priority_lists/presentation/view_models/lists_overview_view_model.dart';

class MockRepository extends Mock implements PriorityListRepository {}

void main() {
  late MockRepository mockRepository;
  late ListsOverviewViewModel viewModel;
  final now = DateTime(2024, 1, 1);

  PriorityList makeList({
    String id = 'list-1',
    String name = 'Test',
    Priority priority = Priority.medium,
  }) {
    return PriorityList(
      id: id,
      name: name,
      colorPreset: ColorPreset.blue,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() {
    mockRepository = MockRepository();
    viewModel = ListsOverviewViewModel(mockRepository);
  });

  setUpAll(() {
    registerFallbackValue(makeList());
  });

  group('ListsOverviewViewModel', () {
    test('loadLists populates lists from repository', () async {
      when(() => mockRepository.getAllLists())
          .thenAnswer((_) async => [makeList()]);

      await viewModel.loadLists();

      expect(viewModel.lists, hasLength(1));
      expect(viewModel.isLoading, false);
      expect(viewModel.error, isNull);
    });

    test('loadLists sets error on failure', () async {
      when(() => mockRepository.getAllLists())
          .thenThrow(Exception('Storage error'));

      await viewModel.loadLists();

      expect(viewModel.lists, isEmpty);
      expect(viewModel.error, contains('Storage error'));
      expect(viewModel.isLoading, false);
    });

    test('createList saves and refreshes', () async {
      when(() => mockRepository.saveList(any()))
          .thenAnswer((_) async {});
      when(() => mockRepository.getAllLists())
          .thenAnswer((_) async => [makeList()]);

      await viewModel.createList('New List', ColorPreset.red, Priority.high);

      verify(() => mockRepository.saveList(any())).called(1);
      verify(() => mockRepository.getAllLists()).called(1);
    });

    test('deleteList removes and refreshes', () async {
      when(() => mockRepository.deleteList('list-1'))
          .thenAnswer((_) async {});
      when(() => mockRepository.getAllLists())
          .thenAnswer((_) async => []);

      await viewModel.deleteList('list-1');

      verify(() => mockRepository.deleteList('list-1')).called(1);
      verify(() => mockRepository.getAllLists()).called(1);
    });

    test('updateList saves and refreshes', () async {
      final list = makeList();
      when(() => mockRepository.saveList(any()))
          .thenAnswer((_) async {});
      when(() => mockRepository.getAllLists())
          .thenAnswer((_) async => [list]);

      await viewModel.updateList(list);

      verify(() => mockRepository.saveList(list)).called(1);
    });

    test('sortedLists returns lists sorted by priority', () async {
      when(() => mockRepository.getAllLists()).thenAnswer((_) async => [
            makeList(id: 'low', name: 'Low', priority: Priority.low),
            makeList(id: 'critical', name: 'Critical', priority: Priority.critical),
            makeList(id: 'high', name: 'High', priority: Priority.high),
          ]);

      await viewModel.loadLists();

      final sorted = viewModel.sortedLists;
      expect(sorted[0].id, 'critical');
      expect(sorted[1].id, 'high');
      expect(sorted[2].id, 'low');
    });
  });
}
