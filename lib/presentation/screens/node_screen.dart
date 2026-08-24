import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/node_tree.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_node.dart';
import '../view_models/auth_view_model.dart';
import '../view_models/filter_view_model.dart';
import '../view_models/node_tree_view_model.dart';
import '../utils/priority_colors.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/bubble_view/bubble_view.dart';
import '../widgets/centered_body.dart';
import '../widgets/move_node_dialog.dart';
import '../widgets/node_form_dialog.dart';
import '../widgets/priority_card.dart';
import '../widgets/priority_filter_bar.dart';

/// One level of the tree.
///
/// The same screen renders the top level ([parentId] == null) and every level
/// below it, so nesting has no ceiling: tapping a child pushes another
/// [NodeScreen] for that child's own children.
class NodeScreen extends StatefulWidget {
  final String? parentId;
  final bool initialBubbleView;

  const NodeScreen({
    super.key,
    this.parentId,
    this.initialBubbleView = false,
  });

  /// Route for drilling into [nodeId]; the name is what breadcrumbs pop back to.
  ///
  /// The view models are handed to the new route explicitly. Providers are
  /// scoped to the subtree they are declared in, and the app's [Navigator]
  /// sits above the ones created after sign-in — so a pushed route built from
  /// the Navigator's context would not find them.
  static Route<void> route(
    BuildContext context,
    String? nodeId, {
    bool bubbleView = false,
  }) {
    final treeViewModel = context.read<NodeTreeViewModel>();
    final filterViewModel = context.read<FilterViewModel>();
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: BreadcrumbBar.routeName(nodeId)),
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider<NodeTreeViewModel>.value(value: treeViewModel),
          ChangeNotifierProvider<FilterViewModel>.value(value: filterViewModel),
        ],
        child: NodeScreen(parentId: nodeId, initialBubbleView: bubbleView),
      ),
    );
  }

  @override
  State<NodeScreen> createState() => _NodeScreenState();
}

class _NodeScreenState extends State<NodeScreen> {
  /// Each level opens as a plain list; the bubble canvas is opt-in and carried
  /// into the next level so the mode sticks while drilling down.
  late bool _showBubbleView;

  bool get _isRoot => widget.parentId == null;

  @override
  void initState() {
    super.initState();
    _showBubbleView = widget.initialBubbleView;
    if (_isRoot) {
      final vm = context.read<NodeTreeViewModel>();
      Future.microtask(() => vm.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NodeTreeViewModel>();
    final filter = context.watch<FilterViewModel>();
    final tree = vm.tree;
    final node = tree.nodeById(widget.parentId);

    // The node backing this screen can be deleted from elsewhere in the tree
    // (a subtree delete higher up); close rather than show a dead level.
    if (!_isRoot && node == null && !vm.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }

    final ancestors = _isRoot
        ? const <PriorityNode>[]
        : tree.pathTo(widget.parentId);
    final accent = node == null ? null : priorityColor(node.priority);

    return Scaffold(
      appBar: AppBar(
        title: Text(node?.title ?? 'Priority Lists'),
        backgroundColor: accent?.withValues(alpha: 0.15),
        bottom: ancestors.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(BreadcrumbBar.height),
                // Drop the current node: it is already the app-bar title.
                child: BreadcrumbBar(
                  ancestors: ancestors.sublist(0, ancestors.length - 1),
                ),
              )
            : null,
        actions: [
          const PriorityFilterBar(),
          IconButton(
            icon: Icon(_showBubbleView ? Icons.view_list : Icons.bubble_chart),
            tooltip: _showBubbleView ? 'List View' : 'Bubble View',
            onPressed: () => setState(() => _showBubbleView = !_showBubbleView),
          ),
          if (node != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => _editNode(vm, node),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(vm, tree, node, popOnDone: true),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: () => context.read<AuthViewModel>().signOut(),
            ),
        ],
      ),
      body: CenteredBody(child: _buildBody(vm, tree, filter)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addChild(vm, node),
        backgroundColor: accent,
        tooltip: node == null ? 'Add top-level node' : 'Add inside "${node.title}"',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(
    NodeTreeViewModel vm,
    NodeTree tree,
    FilterViewModel filter,
  ) {
    if (vm.isLoading && tree.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.error != null && tree.isEmpty) {
      return Center(child: Text('Error: ${vm.error}'));
    }

    final children = tree
        .childrenOf(widget.parentId)
        .where((child) => filter.isVisible(child.priority))
        .toList();

    if (children.isEmpty) {
      final hidden = tree.childrenOf(widget.parentId).isNotEmpty;
      return Center(
        child: Text(
          hidden
              ? 'Everything here is hidden by the priority filter.'
              : 'Nothing here yet.\nTap + to add.',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_showBubbleView) {
      return BubbleView(
        entries: [
          for (final child in children)
            BubbleEntry(
              id: child.id,
              name: child.title,
              color: priorityColor(child.priority),
              priority: child.priority,
              subtitle: _subtitleFor(tree, child),
              chipLabels: _chipLabels(tree, child, filter),
              onTap: () => _openNode(child, bubbleView: true),
              onPriorityUp: child.priority.higher != null
                  ? () => vm.updateNode(
                        child.copyWith(priority: child.priority.higher!),
                      )
                  : null,
              onPriorityDown: child.priority.lower != null
                  ? () => vm.updateNode(
                        child.copyWith(priority: child.priority.lower!),
                      )
                  : null,
              onSetPriority: (p) => vm.updateNode(child.copyWith(priority: p)),
            ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final child = children[index];
        final screenHeight = MediaQuery.of(context).size.height;
        const minCardHeight = 120.0;
        final cardHeight = (screenHeight * child.priority.screenHeightFraction)
            .clamp(minCardHeight, double.infinity);
        final color = priorityColor(child.priority);

        return PriorityCard(
          title: child.title,
          badgeLabel: child.priority.label,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
          fixedHeight: cardHeight,
          childCount: tree.childCount(child.id),
          subtitle: child.description.isEmpty ? null : child.description,
          chipLabels: _chipLabels(tree, child, filter),
          currentPriority: child.priority,
          onTap: () => _openNode(child, bubbleView: false),
          onEdit: () => _editNode(vm, child),
          onDelete: () => _confirmDelete(vm, tree, child),
          onExtract: child.parentId != null
              ? () => _confirmExtract(vm, child)
              : null,
          onMoveInto: () => _showMoveDialog(vm, tree, child),
          onSetPriority: (p) => vm.updateNode(child.copyWith(priority: p)),
        );
      },
    );
  }

  /// Child count once there are children, so the tile says how much is nested
  /// under it; otherwise the node's own description.
  String? _subtitleFor(NodeTree tree, PriorityNode node) {
    final count = tree.childCount(node.id);
    if (count > 0) return '$count inside';
    return node.description.isEmpty ? null : node.description;
  }

  /// Titles of the node's children as mini chips, so one level down is visible
  /// without drilling in. Honors the priority filter, and is skipped for low
  /// nodes whose tiles are too short to fit chips.
  List<String>? _chipLabels(
    NodeTree tree,
    PriorityNode node,
    FilterViewModel filter,
  ) {
    if (node.priority == Priority.low) return null;
    final children = tree
        .childrenOf(node.id)
        .where((child) => filter.isVisible(child.priority))
        .map((child) => child.title)
        .toList();
    return children.isEmpty ? null : children;
  }

  void _openNode(PriorityNode node, {required bool bubbleView}) {
    Navigator.of(context).push(
      NodeScreen.route(context, node.id, bubbleView: bubbleView),
    );
  }

  Future<void> _addChild(NodeTreeViewModel vm, PriorityNode? parent) async {
    final result = await showDialog<NodeFormResult>(
      context: context,
      builder: (_) => NodeFormDialog(parentTitle: parent?.title),
    );
    if (result == null) return;
    await vm.addChild(
      parentId: widget.parentId,
      title: result.title,
      description: result.description,
      priority: result.priority,
      colorPreset: result.colorPreset,
    );
  }

  Future<void> _editNode(NodeTreeViewModel vm, PriorityNode node) async {
    final result = await showDialog<NodeFormResult>(
      context: context,
      builder: (_) => NodeFormDialog(
        initialTitle: node.title,
        initialDescription: node.description,
        initialPriority: node.priority,
        initialColor: node.colorPreset,
      ),
    );
    if (result == null) return;
    await vm.updateNode(
      node.copyWith(
        title: result.title,
        description: result.description,
        priority: result.priority,
        colorPreset: result.colorPreset,
        clearColorPreset: result.colorPreset == null,
      ),
    );
  }

  Future<void> _confirmDelete(
    NodeTreeViewModel vm,
    NodeTree tree,
    PriorityNode node, {
    bool popOnDone = false,
  }) async {
    final descendants = tree.descendantCount(node.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: Text(
          descendants == 0
              ? 'Delete "${node.title}"?'
              : 'Delete "${node.title}" and everything inside '
                  '($descendants node${descendants == 1 ? '' : 's'})?',
        ),
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
    if (confirmed != true) return;

    await vm.deleteNode(node.id);
    if (popOnDone && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmExtract(
    NodeTreeViewModel vm,
    PriorityNode node,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Extract to Top Level'),
        content: Text(
          'Move "${node.title}" out to the top level, keeping what is inside it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Extract'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await vm.moveNode(node.id, null);
    }
  }

  Future<void> _showMoveDialog(
    NodeTreeViewModel vm,
    NodeTree tree,
    PriorityNode node,
  ) async {
    final destination = await MoveNodeDialog.show(
      context,
      tree: tree,
      node: node,
    );
    if (destination == null) return;

    final moved = await vm.moveNode(node.id, destination.parentId);
    if (!moved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not move that node.')),
      );
    }
  }
}
