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

  const NodeScreen({super.key, this.parentId, this.initialBubbleView = false});

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

class _NodeScreenState extends State<NodeScreen> with WidgetsBindingObserver {
  /// Each level opens as a plain list; the bubble canvas is opt-in and carried
  /// into the next level so the mode sticks while drilling down.
  late bool _showBubbleView;

  /// Node being relocated by tap: set from a card's "move into" action, after
  /// which every other card on this level is a drop target. Null when idle.
  String? _movingId;

  bool get _isRoot => widget.parentId == null;

  @override
  void initState() {
    super.initState();
    _showBubbleView = widget.initialBubbleView;
    if (_isRoot) {
      // Only the root screen observes: it stays alive under every pushed
      // level, so one observer covers the whole drill-down.
      WidgetsBinding.instance.addObserver(this);
      final vm = context.read<NodeTreeViewModel>();
      Future.microtask(() => vm.load());
    }
  }

  @override
  void dispose() {
    if (_isRoot) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Another device may have edited the tree while this one was in the
  /// background; pull the latest on return rather than showing stale data.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<NodeTreeViewModel>().refresh();
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
        tooltip: node == null
            ? 'Add top-level node'
            : 'Add inside "${node.title}"',
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

    // The moving node can vanish under us (deleted, filtered out); drop the
    // mode rather than keep a banner for a card that is no longer there.
    final moving = tree.nodeById(_movingId);
    if (_movingId != null &&
        (moving == null || !children.any((c) => c.id == _movingId))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _movingId = null);
      });
    }

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

    final list = _showBubbleView
        ? _buildBubbles(vm, tree, filter, children)
        : _buildList(vm, tree, filter, children);
    if (moving == null) return list;

    return Column(
      children: [
        _MoveBanner(
          title: moving.title,
          onPickFromTree: () => _showMoveDialog(vm, tree, moving),
          onCancel: () => setState(() => _movingId = null),
        ),
        Expanded(child: list),
      ],
    );
  }

  /// Tapping a card opens it — unless a move is in progress, when it means
  /// "put the moving node in here" (or "never mind" on the moving node).
  VoidCallback _tapFor(NodeTreeViewModel vm, PriorityNode child, bool bubble) {
    if (_movingId == null) return () => _openNode(child, bubbleView: bubble);
    if (child.id == _movingId) return () => setState(() => _movingId = null);
    return () => _dropInto(vm, child);
  }

  Future<void> _dropInto(NodeTreeViewModel vm, PriorityNode target) async {
    final movingId = _movingId;
    if (movingId == null) return;
    setState(() => _movingId = null);
    final moved = await vm.moveNode(movingId, target.id);
    if (!moved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not move that node.')),
      );
    }
  }

  Widget _buildBubbles(
    NodeTreeViewModel vm,
    NodeTree tree,
    FilterViewModel filter,
    List<PriorityNode> children,
  ) {
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
            onTap: _tapFor(vm, child, true),
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

  Widget _buildList(
    NodeTreeViewModel vm,
    NodeTree tree,
    FilterViewModel filter,
    List<PriorityNode> children,
  ) {
    // Reorderable so siblings of one priority can be ranked by hand. Flutter
    // gives touch devices a long-press drag and desktops explicit handles.
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: children.length,
      // Dragging starts from the card's own handle only. Wrapping the whole
      // tile in a long-press drag listener steals the gesture from the card's
      // tap, which is how you open a node — and the default handle would land
      // on top of the action row.
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) => vm.reorderChildren(
        parentId: widget.parentId,
        visible: children,
        oldIndex: oldIndex,
        newIndex: newIndex,
      ),
      proxyDecorator: _dragProxy,
      itemBuilder: (context, index) {
        final child = children[index];
        final screenHeight = MediaQuery.of(context).size.height;
        // Enough for the badge row, a line of title and the 1-4 row; below
        // this the title gets clipped instead of merely tight.
        const minCardHeight = 132.0;
        final cardHeight = (screenHeight * child.priority.cardHeightFraction)
            .clamp(minCardHeight, double.infinity);
        final color = priorityColor(child.priority);
        // In move mode every other card is a drop target and says so in
        // green; the moving card itself fades so it reads as "picked up".
        final isMoving = child.id == _movingId;
        final isTarget = _movingId != null && !isMoving;
        final background = isTarget
            ? Colors.green.withValues(alpha: 0.35)
            : color.withValues(alpha: 0.15);

        return KeyedSubtree(
          key: ValueKey(child.id),
          child: Opacity(
            opacity: isMoving ? 0.5 : 1,
            child: PriorityCard(
              title: child.title,
              badgeLabel: isTarget ? 'Put here' : child.priority.label,
              color: isTarget ? Colors.green.shade700 : color,
              backgroundColor: background,
              fixedHeight: cardHeight,
              childCount: tree.childCount(child.id),
              subtitle: child.description.isEmpty ? null : child.description,
              chipLabels: _chipLabels(tree, child, filter),
              currentPriority: child.priority,
              dragIndex: index,
              onTap: _tapFor(vm, child, false),
              onEdit: () => _editNode(vm, child),
              onDelete: () => _confirmDelete(vm, tree, child),
              // One level up, not straight to the top: the grandparent (null
              // when the parent is a root, which is the top level anyway).
              onMoveUp: child.parentId != null
                  ? () => vm.moveNode(
                      child.id,
                      tree.nodeById(child.parentId)?.parentId,
                    )
                  : null,
              onMoveInto: () => setState(() => _movingId = child.id),
              onSetPriority: (p) => vm.updateNode(child.copyWith(priority: p)),
            ),
          ),
        );
      },
    );
  }

  /// Lifts the dragged tile instead of Flutter's default full-width shadow,
  /// which looked detached from the card's own rounded shape.
  Widget _dragProxy(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final lift = Curves.easeInOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.03 * lift,
          child: Material(
            color: Colors.transparent,
            elevation: 8 * lift,
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
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
    Navigator.of(
      context,
    ).push(NodeScreen.route(context, node.id, bubbleView: bubbleView));
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

  /// The full-tree picker, for destinations that are not on this level.
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
    if (mounted) setState(() => _movingId = null);

    final moved = await vm.moveNode(node.id, destination.parentId);
    if (!moved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not move that node.')),
      );
    }
  }
}

/// Strip above the list while a node is being relocated by tap.
class _MoveBanner extends StatelessWidget {
  final String title;
  final VoidCallback onPickFromTree;
  final VoidCallback onCancel;

  const _MoveBanner({
    required this.title,
    required this.onPickFromTree,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.green.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Moving "$title" — tap a node to put it inside',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onPickFromTree,
              child: const Text('Pick from tree…'),
            ),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
