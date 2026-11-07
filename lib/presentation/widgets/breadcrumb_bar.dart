import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/priority_node.dart';
import '../utils/priority_colors.dart';
import '../view_models/last_node_view_model.dart';

/// Root-to-current trail shown under the app bar once you are inside the tree.
///
/// Tapping a crumb jumps straight back to that level. Because every level is a
/// pushed route named `node/<id>`, that is a `popUntil` rather than a new push —
/// so the stack never grows while walking back up.
class BreadcrumbBar extends StatelessWidget {
  /// Ancestors of the current level, root first, excluding the current node.
  final List<PriorityNode> ancestors;

  /// Label for the top level, used by the leading crumb.
  final String rootLabel;

  const BreadcrumbBar({
    super.key,
    required this.ancestors,
    this.rootLabel = 'All',
  });

  /// Tall enough for a finger: the crumbs are the main way back up the tree,
  /// and a 36dp bar left them a ~27dp tap target on a phone.
  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _crumb(
              context,
              label: rootLabel,
              color: onSurface,
              onTap: () => _jumpTo(context, null),
            ),
            for (final node in ancestors) ...[
              Icon(Icons.chevron_right, size: 16, color: onSurface),
              _crumb(
                context,
                label: node.title,
                color: priorityColor(node.priority),
                onTap: () => _jumpTo(context, node.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _crumb(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        // The tap area fills the bar's height and stays at least 44dp wide,
        // so short crumbs ("All", "M1") are still comfortable to hit.
        constraints: const BoxConstraints(minWidth: 44, minHeight: height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String routeName(String? nodeId) => 'node/${nodeId ?? 'root'}';

  void _jumpTo(BuildContext context, String? nodeId) {
    // Looked up before the pops: afterwards this crumb's own route is on its
    // way out and its context is no longer a reliable place to read from.
    final lastNodes = context.read<LastNodeViewModel?>();
    // The crumb's level may have no route of its own — the tree can be
    // re-parented from another device while the user sits deep in it, putting
    // ancestors in the trail that were never pushed. Then the pop falls back
    // to the root, and that is what has to be stored.
    var landedOnCrumb = false;
    Navigator.of(context).popUntil((route) {
      if (route.settings.name == routeName(nodeId)) {
        landedOnCrumb = true;
        return true;
      }
      return route.isFirst;
    });
    // Recorded after the pops, not before: each popped level records the
    // level above it, so the level we landed on has to be the last write
    // enqueued to be the one that ends up stored. The leading crumb, and any
    // crumb that fell back to the root, store "root".
    lastNodes?.remember(landedOnCrumb ? nodeId : null);
  }
}
