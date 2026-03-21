import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../view_models/list_detail_view_model.dart';
import '../../domain/models/priority.dart';
import '../widgets/item_form_dialog.dart';
import '../widgets/list_form_dialog.dart';
import '../widgets/priority_card.dart';

class ListDetailScreen extends StatelessWidget {
  const ListDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ListDetailViewModel>();
    final list = vm.list;
    final sortedItems = vm.sortedItems;
    final listColor = Color(list.colorPreset.colorValue);

    return Scaffold(
      appBar: AppBar(
        title: Text(list.name),
        backgroundColor: listColor.withValues(alpha: 0.15),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editList(context, vm),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDeleteList(context, vm),
          ),
        ],
      ),
      body: sortedItems.isEmpty
          ? const Center(
              child: Text(
                'No items yet.\nTap + to add one.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: sortedItems.length,
              itemBuilder: (context, index) {
                final item = sortedItems[index];

                return PriorityCard(
                  title: item.title,
                  badgeLabel: item.priority.label,
                  color: _priorityColor(item.priority),
                  subtitle: item.description,
                  onEdit: () => _editItem(context, vm, item),
                  onDelete: () => _confirmDeleteItem(
                      context, vm, item.id, item.title),
                  onPriorityUp: item.priority.higher != null
                      ? () => vm.updateItem(
                          item.copyWith(priority: item.priority.higher!))
                      : null,
                  onPriorityDown: item.priority.lower != null
                      ? () => vm.updateItem(
                          item.copyWith(priority: item.priority.lower!))
                      : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addItem(context, vm),
        backgroundColor: listColor,
        child: const Icon(Icons.add),
      ),
    );
  }

  static Color _priorityColor(Priority priority) {
    return switch (priority) {
      Priority.critical => Colors.red.shade400,
      Priority.high => Colors.orange.shade400,
      Priority.medium => Colors.blue.shade400,
      Priority.low => Colors.grey.shade400,
    };
  }

  Future<void> _addItem(BuildContext context, ListDetailViewModel vm) async {
    final result = await showDialog<ItemFormResult>(
      context: context,
      builder: (_) => const ItemFormDialog(),
    );
    if (result != null) {
      await vm.addItem(result.title, result.description, result.priority);
    }
  }

  Future<void> _editItem(
      BuildContext context, ListDetailViewModel vm, item) async {
    final result = await showDialog<ItemFormResult>(
      context: context,
      builder: (_) => ItemFormDialog(
        initialTitle: item.title,
        initialDescription: item.description,
        initialPriority: item.priority,
      ),
    );
    if (result != null) {
      await vm.updateItem(
        item.copyWith(
          title: result.title,
          description: result.description,
          priority: result.priority,
        ),
      );
    }
  }

  Future<void> _confirmDeleteItem(
      BuildContext context, ListDetailViewModel vm, String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "$title"?'),
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
      await vm.deleteItem(id);
    }
  }

  Future<void> _confirmDeleteList(
      BuildContext context, ListDetailViewModel vm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List'),
        content: Text('Delete "${vm.list.name}" and all its items?'),
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
      await vm.deleteList();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _editList(BuildContext context, ListDetailViewModel vm) async {
    final result = await showDialog<ListFormResult>(
      context: context,
      builder: (_) => ListFormDialog(
        initialName: vm.list.name,
        initialColor: vm.list.colorPreset,
      ),
    );
    if (result != null) {
      await vm.updateListDetails(result.name, result.colorPreset);
    }
  }
}
