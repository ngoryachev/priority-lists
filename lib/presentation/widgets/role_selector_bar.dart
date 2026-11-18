import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../domain/models/priority.dart';
import '../../domain/models/priority_node.dart';
import '../view_models/node_tree_view_model.dart';
import 'delete_node_dialog.dart';
import 'node_form_dialog.dart';

/// One chip per role — the tree's top-level nodes — with the active one marked.
/// Designed to sit directly under an [AppBar].
///
/// Tapping another chip makes that role the active one, which is a plain
/// priority write: the active role is simply the red one, and red is already
/// exclusive among siblings, so the role that held it drops to `high` on its
/// own. Tapping the active chip, or long-pressing any of them, opens the menu
/// that renames, recolours, reorders and deletes a role; the trailing "+" chip
/// creates one.
///
/// While a node is being moved by tap ([movingNodeId] set), the chips become
/// drop targets instead: every role the node is not already a direct child of
/// lights up green, and tapping it hands the role to [onDropInto]. The menu and
/// the "+" chip step aside for the duration, so a tap can only mean "put it
/// here".
///
/// The row scrolls horizontally rather than wrapping: on a phone that keeps the
/// bar one line tall, so the list below it does not jump between one and two
/// rows of chrome as roles are picked. More chips than fit a phone's width is
/// the normal case, so the active one is scrolled into view — a marker nobody
/// can see is no marker.
class RoleSelectorBar extends StatefulWidget {
  /// The node being relocated by tap on the level below, or null when idle.
  final String? movingNodeId;

  /// Called with the role the moving node was dropped on. Only used while
  /// [movingNodeId] is set.
  final ValueChanged<PriorityNode>? onDropInto;

  const RoleSelectorBar({super.key, this.movingNodeId, this.onDropInto});

  @override
  State<RoleSelectorBar> createState() => _RoleSelectorBarState();
}

/// What the chip menu can do to a role.
enum _RoleMenuAction { edit, moveLeft, moveRight, delete }

class _RoleSelectorBarState extends State<RoleSelectorBar> {
  /// Keyed by node id, so a chip keeps its key across renames and reorders.
  final Map<String, GlobalKey> _chipKeys = {};

  /// The role the row was last scrolled to, so a rebuild that changes nothing
  /// does not fight the user's own scrolling.
  String? _revealed;

  GlobalKey _keyFor(String id) => _chipKeys.putIfAbsent(id, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NodeTreeViewModel>();
    final roles = vm.tree.rolesInChipOrder;
    // Nothing to mark while the tree is still loading (or failed to): the
    // default role is created once a read comes back empty.
    if (roles.isEmpty) return const SizedBox.shrink();
    final activeId = vm.tree.activeRole?.id;
    // Keys for roles that are gone are of no use to anybody.
    _chipKeys.removeWhere(
      (id, _) => !roles.any((role) => role.id == id),
    );

    _revealAfterFrame(activeId);

    final moving = vm.tree.nodeById(widget.movingNodeId);
    final onDropInto = widget.onDropInto;
    final isMoving = moving != null && onDropInto != null;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (var i = 0; i < roles.length; i++)
              if (isMoving)
                _RoleChip(
                  key: _keyFor(roles[i].id),
                  role: roles[i],
                  isActive: roles[i].id == activeId,
                  // Dropping a node into the role it already sits in directly
                  // would change nothing; from deeper down it lifts the node
                  // to that role's level, which is a real move.
                  isDropTarget: roles[i].id != moving.parentId &&
                      roles[i].id != moving.id,
                  onTap: () => onDropInto(roles[i]),
                )
              else
                _RoleChip(
                  key: _keyFor(roles[i].id),
                  role: roles[i],
                  isActive: roles[i].id == activeId,
                  // The active chip has nothing to switch to, so its tap is
                  // the menu — which is also what a long-press does anywhere.
                  onTap: roles[i].id == activeId
                      ? () => _openMenu(vm, roles, i)
                      : () => _switchTo(vm, roles[i]),
                  onLongPress: () => _openMenu(vm, roles, i),
                ),
            if (!isMoving) _AddRoleChip(onTap: () => _addRole(vm)),
          ],
        ),
      ),
    );
  }

  /// Makes [role] the active one.
  ///
  /// Switching while the user is deep in another role's subtree pops back to
  /// the main screen first: those levels belong to the role being left.
  Future<void> _switchTo(NodeTreeViewModel vm, PriorityNode role) async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    await vm.updateNode(role.copyWith(priority: Priority.critical));
  }

  Future<void> _openMenu(
    NodeTreeViewModel vm,
    List<PriorityNode> roles,
    int index,
  ) async {
    final role = roles[index];
    final chipContext = _chipKeys[role.id]?.currentContext;
    if (chipContext == null) return;
    final box = chipContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final anchor = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );

    final action = await showMenu<_RoleMenuAction>(
      context: context,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(
          value: _RoleMenuAction.edit,
          child: Text('Rename / change colour'),
        ),
        PopupMenuItem(
          value: _RoleMenuAction.moveLeft,
          enabled: index > 0,
          child: const Text('Move left'),
        ),
        PopupMenuItem(
          value: _RoleMenuAction.moveRight,
          enabled: index < roles.length - 1,
          child: const Text('Move right'),
        ),
        PopupMenuItem(
          value: _RoleMenuAction.delete,
          // There is always at least one role: without one the main screen
          // would have no level to show at all.
          enabled: roles.length > 1,
          child: const Text('Delete'),
        ),
      ],
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _RoleMenuAction.edit:
        await _editRole(vm, role);
      case _RoleMenuAction.moveLeft:
        await vm.moveRole(id: role.id, delta: -1);
      case _RoleMenuAction.moveRight:
        await vm.moveRole(id: role.id, delta: 1);
      case _RoleMenuAction.delete:
        await _deleteRole(vm, role);
    }
  }

  Future<void> _editRole(NodeTreeViewModel vm, PriorityNode role) async {
    final result = await showDialog<NodeFormResult>(
      context: context,
      builder: (_) => NodeFormDialog(
        initialTitle: role.title,
        initialDescription: role.description,
        initialPriority: role.priority,
        initialColor: role.colorPreset,
        // A role's priority is what makes it the active one; the chip tap
        // owns that, so the form leaves it alone.
        showPriority: false,
      ),
    );
    if (result == null) return;
    await vm.updateNode(
      role.copyWith(
        title: result.title,
        description: result.description,
        colorPreset: result.colorPreset,
        clearColorPreset: result.colorPreset == null,
      ),
    );
  }

  Future<void> _deleteRole(NodeTreeViewModel vm, PriorityNode role) async {
    final confirmed = await confirmDeleteNode(
      context,
      tree: vm.tree,
      node: role,
    );
    if (!confirmed || !mounted) return;
    // The levels on screen may belong to the role being deleted.
    Navigator.of(context).popUntil((route) => route.isFirst);
    await vm.deleteRole(role.id);
  }

  /// Creates a role at the default low priority, so adding one does not
  /// switch to it — the user picks when to wear it.
  Future<void> _addRole(NodeTreeViewModel vm) async {
    final result = await showDialog<NodeFormResult>(
      context: context,
      builder: (_) => const NodeFormDialog(showPriority: false),
    );
    if (result == null) return;
    // One past the rightmost chip, so the chip the user just made is where
    // they would look for it. Not the number of roles: deleting one leaves
    // its `position` behind as a hole (the level is never renumbered), and a
    // count would then drop the new chip into the middle of the row.
    final roles = vm.rolesInChipOrder;
    final lastPosition = roles.isEmpty ? -1 : roles.last.position;
    await vm.addChild(
      title: result.title,
      description: result.description,
      priority: Priority.low,
      colorPreset: result.colorPreset,
      position: lastPosition + 1,
    );
  }

  /// Brings the active chip into view once the frame that paints it is laid
  /// out — which is how a role restored from storage (or switched to from a
  /// level below) becomes visible when it sits in the trailing, off-screen
  /// part of the row.
  void _revealAfterFrame(String? activeId) {
    if (activeId == _revealed) return;
    _revealed = activeId;
    if (activeId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _chipKeys[activeId]?.currentContext;
      if (!mounted || chipContext == null) return;
      if (_isFullyVisible(chipContext)) return;
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Whether the chip is already wholly inside the viewport. Without this the
  /// row would re-centre on every tap, including taps on chips in plain sight.
  bool _isFullyVisible(BuildContext chipContext) {
    final box = chipContext.findRenderObject();
    // A bar that is no longer laid out — its level was covered by a pushed one
    // in the same frame, as a restored stack does — has nothing to reveal.
    if (box is! RenderBox || !box.attached || !box.hasSize) return true;
    final viewport = RenderAbstractViewport.maybeOf(box);
    final position = Scrollable.maybeOf(chipContext)?.position;
    if (viewport == null || position == null) return true;
    // The scroll offsets at which the chip's leading / trailing edge touches
    // the matching edge of the viewport; between them it is fully in view.
    final leading = viewport.getOffsetToReveal(box, 0).offset;
    final trailing = viewport.getOffsetToReveal(box, 1).offset;
    return position.pixels >= math.min(leading, trailing) &&
        position.pixels <= math.max(leading, trailing);
  }
}

class _RoleChip extends StatelessWidget {
  final PriorityNode role;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Set while a node is being moved: null outside move mode, true when the
  /// node can be dropped here, false when it cannot (the chip is then inert).
  final bool? isDropTarget;

  const _RoleChip({
    super.key,
    required this.role,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
    this.isDropTarget,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A role's own colour when it has one; the theme's accent otherwise.
    final preset = role.colorPreset;
    final accent = preset == null ? scheme.primary : Color(preset.colorValue);
    // Read off the filled chip rather than assumed: the presets are light
    // enough that `onPrimary` would be white on pale green.
    final onAccent = ThemeData.estimateBrightnessForColor(accent) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    final dropTarget = isDropTarget;
    final Widget chip;
    if (dropTarget != null) {
      // Move mode: the same green the cards use for "put it here", so the
      // chips read as part of one set of targets. The active role keeps its
      // bold label as the only reminder of where the user is.
      chip = ChoiceChip(
        label: Text(role.title),
        selected: false,
        onSelected: dropTarget ? (_) => onTap() : null,
        backgroundColor: Colors.green.withValues(alpha: 0.35),
        disabledColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        labelStyle: TextStyle(
          color: dropTarget
              ? scheme.onSurface
              : scheme.onSurface.withValues(alpha: 0.38),
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
        showCheckmark: false,
        side: BorderSide(
          color: dropTarget ? Colors.green : scheme.outlineVariant,
          width: dropTarget ? 1.5 : 1,
        ),
      );
    } else {
      chip = ChoiceChip(
        label: Text(role.title),
        selected: isActive,
        onSelected: (_) => onTap(),
        selectedColor: accent,
        labelStyle: TextStyle(
          color: isActive ? onAccent : scheme.onSurface,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
        showCheckmark: false,
        side: BorderSide(color: isActive ? accent : scheme.outlineVariant),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: role.description.isEmpty
            ? chip
            : Tooltip(message: role.description, child: chip),
      ),
    );
  }
}

class _AddRoleChip extends StatelessWidget {
  final VoidCallback onTap;

  const _AddRoleChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: 'Add a role',
        child: ActionChip(
          // A literal "+" rather than an icon: the level's own FAB already
          // owns the add icon, and two of them on one screen read as the
          // same button.
          label: const Text('+', style: TextStyle(fontSize: 16)),
          onPressed: onTap,
        ),
      ),
    );
  }
}
