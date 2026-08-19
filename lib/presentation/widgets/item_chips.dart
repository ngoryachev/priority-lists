import 'package:flutter/material.dart';

/// Compact chips with truncated item titles, shown on every list tile tall
/// enough to fit them so their tasks are visible right from the top level.
class ItemChips extends StatelessWidget {
  final List<String> labels;
  final Color color;
  final int maxChips;
  final int maxTitleChars;
  final double fontSize;
  final WrapAlignment alignment;

  const ItemChips({
    super.key,
    required this.labels,
    required this.color,
    this.maxChips = 6,
    this.maxTitleChars = 16,
    this.fontSize = 11,
    this.alignment = WrapAlignment.start,
  });

  String _shorten(String title) => title.length > maxTitleChars
      ? '${title.substring(0, maxTitleChars - 1)}…'
      : title;

  @override
  Widget build(BuildContext context) {
    final visible = labels.take(maxChips).toList();
    final overflow = labels.length - visible.length;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: alignment,
      children: [
        for (final label in visible) _chip(_shorten(label)),
        if (overflow > 0) _chip('+$overflow'),
      ],
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.55,
        vertical: fontSize * 0.2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
