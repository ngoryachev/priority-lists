import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/repositories/priority_list_repository.dart';
import '../view_models/list_detail_view_model.dart';
import '../view_models/lists_overview_view_model.dart';
import '../widgets/list_card.dart';
import '../widgets/list_form_dialog.dart';
import 'list_detail_screen.dart';

class ListsOverviewScreen extends StatefulWidget {
  const ListsOverviewScreen({super.key});

  @override
  State<ListsOverviewScreen> createState() => _ListsOverviewScreenState();
}

class _ListsOverviewScreenState extends State<ListsOverviewScreen> {
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
      ),
      body: _buildBody(vm),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, vm),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(ListsOverviewViewModel vm) {
    if (vm.isLoading) {
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

    final sortedLists = vm.sortedLists;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sortedLists.length,
      itemBuilder: (context, index) {
        final list = sortedLists[index];
        return ListCard(
          list: list,
          onTap: () => _openList(context, list),
          onEdit: () => _showEditDialog(context, vm, list),
          onDelete: () => _confirmDelete(context, vm, list.id, list.name),
        );
      },
    );
  }

  Future<void> _openList(BuildContext context, priorityList) async {
    final repository = context.read<PriorityListRepository>();
    final vm = context.read<ListsOverviewViewModel>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => ListDetailViewModel(repository, priorityList),
          child: const ListDetailScreen(),
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

  Future<void> _showEditDialog(
      BuildContext context, ListsOverviewViewModel vm, priorityList) async {
    final result = await showDialog<ListFormResult>(
      context: context,
      builder: (_) => ListFormDialog(
        initialName: priorityList.name,
        initialColor: priorityList.colorPreset,
        initialPriority: priorityList.priority,
      ),
    );
    if (result != null) {
      await vm.updateList(
        priorityList.copyWith(
          name: result.name,
          colorPreset: result.colorPreset,
          priority: result.priority,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, ListsOverviewViewModel vm, String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List'),
        content: Text('Delete "$name" and all its items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await vm.deleteList(id);
    }
  }
}
