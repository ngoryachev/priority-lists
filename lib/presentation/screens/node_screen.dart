import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/node_tree.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_node.dart';
import '../../domain/repositories/activity_log_repository.dart';
import '../view_models/auth_view_model.dart';
import '../view_models/card_page_view_model.dart';
import '../view_models/filter_view_model.dart';
import '../view_models/last_node_view_model.dart';
import '../view_models/node_tree_view_model.dart';
import '../view_models/role_time_view_model.dart';
import '../utils/priority_colors.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/bubble_view/bubble_view.dart';
import '../widgets/centered_body.dart';
import '../widgets/delete_node_dialog.dart';
import '../widgets/move_node_dialog.dart';
import '../widgets/node_form_dialog.dart';
import '../widgets/priority_card.dart';
import '../widgets/priority_filter_bar.dart';
import '../widgets/role_selector_bar.dart';
import '../widgets/role_time_strip.dart';
import 'activity_log_screen.dart';

/// One level of the tree.
///
/// The same screen renders the main screen ([parentId] == null, which shows the
/// children of the active role) and every level below it, so nesting has no
/// ceiling: tapping a child pushes another [NodeScreen] for that child's own
/// children.
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
    bool animate = true,
  }) {
    final treeViewModel = context.read<NodeTreeViewModel>();
    final filterViewModel = context.read<FilterViewModel>();
    final lastNodeViewModel = context.read<LastNodeViewModel?>();
    final cardPageViewModel = context.read<CardPageViewModel?>();
    final roleTimeViewModel = context.read<RoleTimeViewModel?>();
    final settings = RouteSettings(name: BreadcrumbBar.routeName(nodeId));
    Widget build(BuildContext _) => MultiProvider(
      providers: [
        ChangeNotifierProvider<NodeTreeViewModel>.value(value: treeViewModel),
        ChangeNotifierProvider<FilterViewModel>.value(value: filterViewModel),
        if (lastNodeViewModel != null)
          Provider<LastNodeViewModel>.value(value: lastNodeViewModel),
        if (cardPageViewModel != null)
          Provider<CardPageViewModel>.value(value: cardPageViewModel),
        if (roleTimeViewModel != null)
          ChangeNotifierProvider<RoleTimeViewModel>.value(
            value: roleTimeViewModel,
          ),
      ],
      child: NodeScreen(parentId: nodeId, initialBubbleView: bubbleView),
    );
    return animate
        ? MaterialPageRoute<void>(settings: settings, builder: build)
        : _InstantPageRoute<void>(settings: settings, builder: build);
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

  /// Where the user left off, so every level change can be recorded. Nullable:
  /// screens built without it (tests, older entry points) just do not persist.
  LastNodeViewModel? _lastNodes;

  /// Which child page every card on this level was left on. Nullable for the
  /// same reason as [_lastNodes]: screens built without it simply always open
  /// their cards on page 0.
  CardPageViewModel? _cardPages;

  /// The level this screen pops back to, cached while this screen's node is
  /// still in the tree. Null means the top level.
  ///
  /// It has to be a cache: the pop can be triggered *because* the node went
  /// away (a subtree delete higher up), and by then the tree can no longer
  /// say what sat above it.
  String? _parentLevelId;

  /// Restoring the saved level is a launch-time, one-shot affair; a later
  /// reload of the tree must not drag the user back down. After it, coming
  /// back to the foreground follows another device instead
  /// ([_followOtherDevice]).
  bool _restored = false;

  bool get _isRoot => widget.parentId == null;

  @override
  void initState() {
    super.initState();
    _showBubbleView = widget.initialBubbleView;
    // Captured now rather than read from the callbacks below: a pop fires
    // while this screen is on its way out, and the restore pushes run after
    // an await.
    _lastNodes = context.read<LastNodeViewModel?>();
    _cardPages = context.read<CardPageViewModel?>();
    // Pages from another device arrive through a reload; every level rebuilds
    // its cards onto them.
    _cardPages?.revision.addListener(_onCardPagesReloaded);
    if (_isRoot) {
      // Only the root screen observes: it stays alive under every pushed
      // level, so one observer covers the whole drill-down.
      WidgetsBinding.instance.addObserver(this);
      final vm = context.read<NodeTreeViewModel>();
      // Nothing is awaited before the first frame: the loading and error
      // states of the tree are untouched, and the stack is only rebuilt once
      // there is a tree to look the saved node up in.
      final cardPages = _cardPages;
      Future.microtask(() async {
        // The pages are in before the first card is built, so a card never
        // mounts on page 0 and then jumps.
        await Future.wait([vm.load(), if (cardPages != null) cardPages.reload()]);
        if (!mounted) return;
        await _restoreLastLevel(vm);
      });
    }
  }

  /// Reopens the level the user was last on by pushing one route per node of
  /// its root-to-node path, so breadcrumbs and back navigation behave exactly
  /// as if the user had drilled down by hand.
  ///
  /// Anything that goes wrong — no settings store, a pointer from another
  /// account, a node that is gone, a store that throws — leaves the user at
  /// the root, which is where they already are.
  Future<void> _restoreLastLevel(NodeTreeViewModel vm) async {
    final lastNodes = _lastNodes;
    if (lastNodes == null || _restored) return;
    // No tree means nothing to resolve the pointer against: a load that
    // failed, or an account with nothing in it. The flag stays unburned so a
    // resume that does bring a tree in can still restore — `refresh` never
    // clears `error`, so testing the tree is both truer and the only check
    // that a later success can pass.
    if (vm.tree.isEmpty) return;
    _restored = true;
    final path = await lastNodes.resolveRestorePath(vm.tree);
    if (path.isEmpty || !mounted) return;
    // The tree paints before this read comes back, so the user can tap a card
    // in between. Their navigation is newer than the stored pointer — and has
    // already overwritten it — so leave their stack alone rather than pile a
    // restored one on top of it.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final navigator = Navigator.of(context);
    for (final node in path) {
      // Animation-free, or the app would visibly fan through every level on
      // the way down.
      navigator.push(NodeScreen.route(context, node.id, animate: false));
    }
  }

  /// Moves this device to the level another device left, when the app comes
  /// back to the foreground — the same moment the tree itself is refreshed.
  ///
  /// Only from a plain level: a dialog, a sheet or another screen on top is
  /// left alone, and so is a read that gives nothing to go on. The stack is
  /// rebuilt like a launch restore, so back navigation and breadcrumbs behave
  /// as if the user had drilled down by hand.
  Future<void> _followOtherDevice(NodeTreeViewModel vm) async {
    final lastNodes = _lastNodes;
    if (lastNodes == null || vm.tree.isEmpty) return;
    final path = await lastNodes.resolveFollowPath(vm.tree);
    if (path == null || !mounted) return;
    final navigator = Navigator.of(context);
    // The route on top, found without popping anything.
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final current = top;
    if (current == null) return;
    final currentName = current.isFirst
        ? BreadcrumbBar.routeName(null)
        : current.settings.name;
    if (currentName == null || !currentName.startsWith('node/')) return;
    final targetId = path.isEmpty ? null : path.last.id;
    if (currentName == BreadcrumbBar.routeName(targetId)) return;
    if (path.isEmpty) {
      navigator.popUntil((route) => route.isFirst);
    } else {
      // The old levels are removed under the new one rather than popped: a
      // pop animates (and flies the heroes) while the instant push lands in
      // the same frame.
      navigator.pushAndRemoveUntil(
        NodeScreen.route(context, path.first.id, animate: false),
        (route) => route.isFirst,
      );
      for (final node in path.skip(1)) {
        navigator.push(NodeScreen.route(context, node.id, animate: false));
      }
    }
    // A popped level records the one above it on its way out; the level we
    // have landed on has to be the last write.
    lastNodes.remember(targetId);
  }

  void _onCardPagesReloaded() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cardPages?.revision.removeListener(_onCardPagesReloaded);
    if (_isRoot) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Another device may have edited the tree, or moved around it, while this
  /// one was in the background; pull the latest on return rather than
  /// showing stale data.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final vm = context.read<NodeTreeViewModel>();
    final cardPages = _cardPages;
    final roleTime = context.read<RoleTimeViewModel?>();
    Future.microtask(() async {
      await Future.wait([
        if (roleTime != null) roleTime.refresh(),
        vm.refresh(),
        if (cardPages != null) cardPages.reload(),
      ]);
      if (!mounted) return;
      if (_restored) {
        await _followOtherDevice(vm);
      } else {
        // A launch whose own load failed has not restored yet: a tree
        // arriving here is its retry.
        await _restoreLastLevel(vm);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NodeTreeViewModel>();
    final filter = context.watch<FilterViewModel>();
    final tree = vm.tree;
    final node = _isRoot ? null : tree.nodeById(widget.parentId);
    // Which level is listed below. The main screen shows the active role's
    // children, so the role is this screen's level without being a node the
    // user drilled into — [node] stays null there, which is what keeps the
    // History and Sign Out actions (and keeps Edit / Delete off the role).
    final levelNode = _isRoot ? tree.activeRole : node;
    final levelId = levelNode?.id;

    // The node backing this screen can be deleted from elsewhere in the tree
    // (a subtree delete higher up); close rather than show a dead level.
    if (!_isRoot && node == null && !vm.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }

    final ancestors = _isRoot
        ? const <PriorityNode>[]
        : _trailTo(tree, widget.parentId);
    // Remembered while the node is still here, for the pop that may be caused
    // by it disappearing. A child of the role pops back to the main screen,
    // which is `null` — the role is never a level of its own.
    if (node != null) {
      final parentId = node.parentId;
      _parentLevelId = parentId == tree.activeRole?.id ? null : parentId;
    }
    // What tints the app bar and the FAB: a drilled-in node by its priority,
    // the active role by its own colour when it has one.
    final accent = levelNode == null
        ? null
        : _isRoot
            ? _roleColor(levelNode)
            : priorityColor(levelNode.priority);

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(levelNode?.title ?? 'Priority Lists'),
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
          ] else ...[
            // Nullable lookup: the log is an optional extra, and screens built
            // without it (tests, older entry points) simply hide the button.
            if (context.read<ActivityLogRepository?>() != null)
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'History',
                onPressed: () => Navigator.of(
                  context,
                ).push(ActivityLogScreen.route(context)),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: () => context.read<AuthViewModel>().signOut(),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Pinned: the roles stay visible while drilling down, which is the
          // point of them.
          // While a node is being moved the chips are drop targets too, so it
          // can go straight into another role.
          RoleSelectorBar(
            movingNodeId: _movingId,
            onDropInto: (role) => _dropInto(vm, role),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CenteredBody(
                    child: _buildBody(vm, tree, filter, levelId),
                  ),
                ),
                // Along the right edge of the whole list: today's time per
                // role, in the roles' colours.
                const Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: RoleTimeStrip(),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addChild(vm, levelNode),
        backgroundColor: accent,
        tooltip: levelNode == null
            ? 'Add a role'
            : 'Add inside "${levelNode.title}"',
        child: const Icon(Icons.add),
      ),
    );

    if (_isRoot) return scaffold;
    // One hook for every way up: the system back gesture, the app bar's back
    // button, predictive back, the `maybePop` fired when this screen's node
    // disappears, and each level a breadcrumb jump pops through.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _lastNodes?.remember(_parentLevelId);
      },
      child: scaffold,
    );
  }

  /// The trail of ancestors a level shows in its breadcrumbs.
  ///
  /// The active role is dropped from it: the role's level *is* the main
  /// screen, which the leading "All" crumb already stands for, and the role
  /// has no level of its own to jump to.
  List<PriorityNode> _trailTo(NodeTree tree, String? id) {
    final path = tree.pathTo(id);
    if (path.isNotEmpty && path.first.id == tree.activeRole?.id) {
      return path.sublist(1);
    }
    return path;
  }

  Widget _buildBody(
    NodeTreeViewModel vm,
    NodeTree tree,
    FilterViewModel filter,
    String? levelId,
  ) {
    if (vm.isLoading && tree.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.error != null && tree.isEmpty) {
      return Center(child: Text('Error: ${vm.error}'));
    }

    final children = tree
        .childrenOf(levelId)
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
      final hidden = tree.childrenOf(levelId).isNotEmpty;
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
        : _buildList(vm, tree, filter, children, levelId);
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
    String? levelId,
  ) {
    // One height for every tile, whatever its priority and however tall the
    // screen: the badge row, one line of title and the 1-4 row, and nothing
    // else. Priority is carried by the colour and the badge. Read once here
    // rather than per tile, so there is only one number in play.
    final cardHeight = PriorityCard.compactHeight(context);

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
        parentId: levelId,
        visible: children,
        oldIndex: oldIndex,
        newIndex: newIndex,
      ),
      proxyDecorator: _dragProxy,
      itemBuilder: (context, index) {
        final child = children[index];
        final color = priorityColor(child.priority);
        // In move mode every other card is a drop target and says so in
        // green; the moving card itself fades so it reads as "picked up".
        final isMoving = child.id == _movingId;
        final isTarget = _movingId != null && !isMoving;
        final background = isTarget
            ? Colors.green.withValues(alpha: 0.35)
            : color.withValues(alpha: 0.15);
        // The level the card can be lifted to: its grandparent, which a child
        // of a role does not have.
        final moveUpTarget = tree.nodeById(child.parentId)?.parentId;

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
              currentPriority: child.priority,
              dragIndex: index,
              childPages: _childPagesFor(vm, tree, filter, child),
              initialChildId: _cardPages?.childFor(child.id),
              onChildPageChanged: (id) => _cardPages?.remember(child.id, id),
              onTap: _tapFor(vm, child, false),
              onEdit: () => _editNode(vm, child),
              onDelete: () => _confirmDelete(vm, tree, child),
              // One level up, not straight to the top — and only when there
              // is a level above: a child of a role has none, and lifting it
              // further would turn it into a role of its own.
              onMoveUp: moveUpTarget == null
                  ? null
                  : () => vm.moveNode(child.id, moveUpTarget),
              onMoveInto: () => setState(() => _movingId = child.id),
              onSetPriority: (p) => vm.updateNode(child.copyWith(priority: p)),
            ),
          ),
        );
      },
    );
  }

  /// The second, horizontal axis of a list tile: one page per direct child of
  /// [node], in the tree's own order (priority, then the manual position, then
  /// age) and honouring the priority filter.
  ///
  /// A child page is action-light on purpose — the owner-only actions and the
  /// reorder handle belong to the level the child lives on. What it does carry
  /// is the same tap (through [_openNode], so the level is recorded) and the
  /// same priority write (through [NodeTreeViewModel.updateNode], so the
  /// critical-priority exclusivity applies) as a card on that level.
  List<PriorityCardPage> _childPagesFor(
    NodeTreeViewModel vm,
    NodeTree tree,
    FilterViewModel filter,
    PriorityNode node,
  ) {
    // A move in progress turns every card into a drop target whose tap means
    // "put it here"; swiping to another node's face there would be lying
    // about what the tap does, so the pages go away until the move is over.
    // The remembered page is untouched and comes back with them.
    if (_movingId != null) return const [];
    return [
      for (final child
          in tree
              .childrenOf(node.id)
              .where((child) => filter.isVisible(child.priority)))
        PriorityCardPage(
          id: child.id,
          title: child.title,
          badgeLabel: child.priority.label,
          color: priorityColor(child.priority),
          backgroundColor: priorityColor(
            child.priority,
          ).withValues(alpha: 0.15),
          childCount: tree.childCount(child.id),
          currentPriority: child.priority,
          onTap: () => _openNode(child, bubbleView: false),
          onSetPriority: (p) => vm.updateNode(child.copyWith(priority: p)),
        ),
    ];
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
  /// without drilling in — the bubble view's doing; list tiles carry only the
  /// child count. Honors the priority filter, and is skipped for low nodes
  /// whose bubbles are too small to fit chips.
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
    _lastNodes?.remember(node.id);
    Navigator.of(
      context,
    ).push(NodeScreen.route(context, node.id, bubbleView: bubbleView));
  }

  /// The colour a role tints its level with: its own when it has one, and
  /// otherwise the colour of its priority, like any other node.
  Color _roleColor(PriorityNode role) {
    final preset = role.colorPreset;
    return preset == null
        ? priorityColor(role.priority)
        : Color(preset.colorValue);
  }

  /// Adds a child of [parent] — the active role on the main screen, this
  /// screen's node below it.
  Future<void> _addChild(NodeTreeViewModel vm, PriorityNode? parent) async {
    final result = await showDialog<NodeFormResult>(
      context: context,
      builder: (_) => NodeFormDialog(parentTitle: parent?.title),
    );
    if (result == null) return;
    await vm.addChild(
      parentId: parent?.id,
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
    final confirmed = await confirmDeleteNode(context, tree: tree, node: node);
    if (!confirmed) return;

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

/// A level pushed without its forward transition.
///
/// Restoring a deep level pushes one route per level in a single frame; with
/// the normal 300ms slide the app would fan through every ancestor on launch.
/// Only the forward direction is zeroed — walking back up a restored stack
/// animates like any other pop.
class _InstantPageRoute<T> extends MaterialPageRoute<T> {
  _InstantPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => Duration.zero;
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
                'Moving "$title" — tap a node or a role to put it inside',
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
