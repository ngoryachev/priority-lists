import 'package:flutter/material.dart';

import '../../domain/models/node_tree.dart';
import '../../domain/models/priority_node.dart';
import '../utils/priority_colors.dart';

/// Chosen destination for a move. Wraps the id because null is meaningful
/// (the top level) and must not read as "dialog dismissed".
class MoveDestination {
  final String? parentId;
  const MoveDestination(this.parentId);
}

/// Picks a new parent for [node] anywhere in the tree.
///
/// The node itself and its own subtree are absent from the list — moving into
/// them would either be a no-op or cut the subtree loose from the root.
class MoveNodeDialog extends StatefulWidget {
  final NodeTree tree;
  final PriorityNode node;

  const MoveNodeDialog({super.key, required this.tree, required this.node});

  static Future<MoveDestination?> show(
    BuildContext context, {
    required NodeTree tree,
    required PriorityNode node,
  }) {
    return showDialog<MoveDestination>(
      context: context,
      builder: (_) => MoveNodeDialog(tree: tree, node: node),
    );
  }

  @override
  State<MoveNodeDialog> createState() => _MoveNodeDialogState();
}

class _MoveNodeDialogState extends State<MoveNodeDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tree = widget.tree;
    final candidates = tree.moveTargetsFor(widget.node.id).where((candidate) {
      if (_query.isEmpty) return true;
      return candidate.title.toLowerCase().contains(_query);
    }).toList();

    return AlertDialog(
      title: Text('Move "${widget.node.title}" into...'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (_query.isEmpty && !widget.node.isRoot)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.north)),
                      title: const Text('Top level'),
                      subtitle: const Text('No parent'),
                      onTap: () => Navigator.of(context)
                          .pop(const MoveDestination(null)),
                    ),
                  for (final candidate in candidates)
                    _targetTile(context, tree, candidate),
                  if (candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nowhere to move it to.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _targetTile(BuildContext context, NodeTree tree, PriorityNode target) {
    final color = priorityColor(target.priority);
    final isCurrentParent = target.id == widget.node.parentId;
    final childCount = tree.childCount(target.id);

    return Padding(
      // Indentation is what makes the flat list readable as a tree.
      padding: EdgeInsets.only(left: 16.0 * tree.depthOf(target.id)),
      child: ListTile(
        dense: true,
        enabled: !isCurrentParent,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(
            tree.hasChildren(target.id) ? Icons.folder_outlined : Icons.circle,
            size: 14,
            color: color,
          ),
        ),
        title: Text(target.title, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          isCurrentParent
              ? 'Current parent'
              : '$childCount child${childCount == 1 ? '' : 'ren'}',
        ),
        onTap: isCurrentParent
            ? null
            : () => Navigator.of(context).pop(MoveDestination(target.id)),
      ),
    );
  }
}
