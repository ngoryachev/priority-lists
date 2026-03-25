import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/priority.dart';
import '../../domain/repositories/priority_list_repository.dart';
import '../view_models/auth_view_model.dart';
import '../view_models/list_detail_view_model.dart';
import '../view_models/lists_overview_view_model.dart';
import '../widgets/list_form_dialog.dart';
import '../widgets/bubble_view/bubble_view.dart';
import '../widgets/priority_card.dart';
import 'list_detail_screen.dart';

class ListsOverviewScreen extends StatefulWidget {
  const ListsOverviewScreen({super.key});

  @override
  State<ListsOverviewScreen> createState() => _ListsOverviewScreenState();
}

class _ListsOverviewScreenState extends State<ListsOverviewScreen> {
  bool _showBubbleView = true;
  bool _hideLow = false;

  @override
  void initState() {
    super.initState();
    final vm = context.read<ListsOverviewViewModel>();
    Future.microtask(() => vm.loadLists());
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ListsOverviewViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Priority Lists'),
        actions: [
          IconButton(
            icon: Icon(_hideLow ? Icons.visibility_off : Icons.visibility),
            tooltip: _hideLow ? 'Show Low' : 'Hide Low',
            onPressed: () => setState(() => _hideLow = !_hideLow),
          ),
          IconButton(
            icon: Icon(_showBubbleView ? Icons.view_list : Icons.bubble_chart),
            tooltip: _showBubbleView ? 'List View' : 'Bubble View',
            onPressed: () => setState(() => _showBubbleView = !_showBubbleView),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => context.read<AuthViewModel>().signOut(),
          ),
        ],
      ),
      body: _buildBody(vm),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, vm),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<dynamic> _filteredLists(ListsOverviewViewModel vm) {
    final lists = vm.sortedLists;
    if (_hideLow) {
      return lists.where((l) => l.priority != Priority.low).toList();
    }
    return lists;
  }

  Widget _buildBody(ListsOverviewViewModel vm) {
    if (vm.isLoading && vm.lists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vm.error != null) {
      return Center(child: Text('Error: ${vm.error}'));
    }

    if (vm.lists.isEmpty) {
      return const Center(
        child: Text('No lists yet.\nTap + to create one.', textAlign: TextAlign.center),
      );
    }

    final sortedLists = _filteredLists(vm);

    if (_showBubbleView) {
      return BubbleView(
        entries: sortedLists
            .map((list) => BubbleEntry(
                  id: list.id,
                  name: list.name,
                  color: Color(list.colorPreset.colorValue),
                  priority: list.priority,
                  subtitle: '${list.items.length} item${list.items.length == 1 ? '' : 's'}',
                  onTap: () => _openList(context, list, useBubbleView: true),
                  onPriorityUp: list.priority.higher != null
                      ? () => vm.updateList(list.copyWith(
                            priority: list.priority.higher!,
                            updatedAt: DateTime.now(),
                          ))
                      : null,
                  onPriorityDown: list.priority.lower != null
                      ? () => vm.updateList(list.copyWith(
                            priority: list.priority.lower!,
                            updatedAt: DateTime.now(),
                          ))
                      : null,
                ))
            .toList(),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sortedLists.length,
      itemBuilder: (context, index) {
        final list = sortedLists[index];
        final screenHeight = MediaQuery.of(context).size.height;
        const minCardHeight = 120.0;
        final cardHeight = (screenHeight * list.priority.screenHeightFraction).clamp(minCardHeight, double.infinity);
        final listColor = Color(list.colorPreset.colorValue);
        return PriorityCard(
          title: list.name,
          badgeLabel: list.priority.label,
          color: listColor,
          backgroundColor: listColor.withValues(alpha: 0.15),
          fixedHeight: cardHeight,
          subtitle: '${list.items.length} item${list.items.length == 1 ? '' : 's'}',
          onTap: () => _openList(context, list, useBubbleView: false),
          onPriorityUp: list.priority.higher != null
              ? () => vm.updateList(list.copyWith(
                    priority: list.priority.higher!,
                    updatedAt: DateTime.now(),
                  ))
              : null,
          onPriorityDown: list.priority.lower != null
              ? () => vm.updateList(list.copyWith(
                    priority: list.priority.lower!,
                    updatedAt: DateTime.now(),
                  ))
              : null,
        );
      },
    );
  }

  Future<void> _openList(BuildContext context, priorityList, {required bool useBubbleView}) async {
    final repository = context.read<PriorityListRepository>();
    final vm = context.read<ListsOverviewViewModel>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => ListDetailViewModel(repository, priorityList),
          child: ListDetailScreen(initialBubbleView: useBubbleView),
        ),
      ),
    );
    if (mounted) {
      vm.loadLists();
    }
  }

  Future<void> _showCreateDialog(
      BuildContext context, ListsOverviewViewModel vm) async {
    final result = await showDialog<ListFormResult>(
      context: context,
      builder: (_) => const ListFormDialog(),
    );
    if (result != null) {
      await vm.createList(result.name, result.colorPreset, result.priority);
    }
  }
}
