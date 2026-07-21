import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/repositories/priority_list_repository.dart';
import '../view_models/auth_view_model.dart';
import '../view_models/list_detail_view_model.dart';
import '../view_models/filter_view_model.dart';
import '../view_models/lists_overview_view_model.dart';
import '../utils/priority_colors.dart';
import '../widgets/centered_body.dart';
import '../widgets/list_form_dialog.dart';
import '../widgets/bubble_view/bubble_view.dart';
import '../widgets/priority_card.dart';
import '../widgets/priority_filter_bar.dart';
import 'list_detail_screen.dart';

class ListsOverviewScreen extends StatefulWidget {
  const ListsOverviewScreen({super.key});

  @override
  State<ListsOverviewScreen> createState() => _ListsOverviewScreenState();
}

class _ListsOverviewScreenState extends State<ListsOverviewScreen> {
  bool _showBubbleView = true;

  @override
  void initState() {
    super.initState();
    final vm = context.read<ListsOverviewViewModel>();
    Future.microtask(() => vm.loadLists());
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ListsOverviewViewModel>();
    final filter = context.watch<FilterViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Priority Lists'),
        actions: [
          const PriorityFilterBar(),
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
      body: CenteredBody(child: _buildBody(vm, filter)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, vm),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<dynamic> _filteredLists(
      ListsOverviewViewModel vm, FilterViewModel filter) {
    return vm.sortedLists.where((l) => filter.isVisible(l.priority)).toList();
  }

  Widget _buildBody(ListsOverviewViewModel vm, FilterViewModel filter) {
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

    final sortedLists = _filteredLists(vm, filter);

    if (_showBubbleView) {
      return BubbleView(
        entries: sortedLists
            .map((list) => BubbleEntry(
                  id: list.id,
                  name: list.name,
                  color: priorityColor(list.priority),
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
                  onSetPriority: (p) => vm.updateList(list.copyWith(
                        priority: p,
                        updatedAt: DateTime.now(),
                      )),
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
        final listColor = priorityColor(list.priority);
        return PriorityCard(
          title: list.name,
          badgeLabel: list.priority.label,
          color: listColor,
          backgroundColor: listColor.withValues(alpha: 0.15),
          fixedHeight: cardHeight,
          subtitle: '${list.items.length} item${list.items.length == 1 ? '' : 's'}',
          currentPriority: list.priority,
          onTap: () => _openList(context, list, useBubbleView: false),
          onMoveInto: sortedLists.length > 1
              ? () => _showMoveIntoDialog(context, vm, list)
              : null,
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
          onSetPriority: (p) => vm.updateList(list.copyWith(
            priority: p,
            updatedAt: DateTime.now(),
          )),
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

  Future<void> _showMoveIntoDialog(
      BuildContext context, ListsOverviewViewModel vm, dynamic sourceList) async {
    final targets = vm.sortedLists.where((l) => l.id != sourceList.id).toList();
    if (targets.isEmpty) return;

    final selected = await showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move "${sourceList.name}" into...'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: targets.length,
            itemBuilder: (context, index) {
              final target = targets[index];
              final color = priorityColor(target.priority);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Icon(Icons.list, color: color),
                ),
                title: Text(target.name),
                subtitle: Text('${target.items.length} item${target.items.length == 1 ? '' : 's'}'),
                onTap: () => Navigator.of(context).pop(target),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null) {
      await vm.moveListIntoList(sourceList.id, selected.id);
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
