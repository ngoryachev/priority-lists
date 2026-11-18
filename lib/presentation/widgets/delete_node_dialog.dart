import 'package:flutter/material.dart';

import '../../domain/models/node_tree.dart';
import '../../domain/models/priority_node.dart';

/// Asks before deleting [node], saying how much goes with it.
///
/// A delete takes the whole subtree, so the count is the point of the dialog:
/// "Delete \"Work\"?" and "Delete \"Work\" and everything inside (12 nodes)?"
/// are very different questions. Returns true only when the user confirmed.
///
/// Lives on its own because two places ask it: a card's delete action (and the
/// level's own app bar) and the chip menu of a role.
Future<bool> confirmDeleteNode(
  BuildContext context, {
  required NodeTree tree,
  required PriorityNode node,
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
  return confirmed == true;
}
