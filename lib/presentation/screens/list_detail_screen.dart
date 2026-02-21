import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../view_models/list_detail_view_model.dart';
import '../widgets/item_form_dialog.dart';
import '../widgets/list_form_dialog.dart';
import '../widgets/priority_item_card.dart';

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
                final screenHeight = MediaQuery.of(context).size.height;
                final itemHeight =
                    screenHeight * item.priority.screenHeightFraction;

                return PriorityItemCard(
                  item: item,
                  height: itemHeight,
                  onEdit: () => _editItem(context, vm, item),
                  onDelete: () => _confirmDeleteItem(
                      context, vm, item.id, item.title),
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
