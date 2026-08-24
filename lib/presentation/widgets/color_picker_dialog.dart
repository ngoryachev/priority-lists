import 'package:flutter/material.dart';

import '../../domain/models/color_preset.dart';

/// Result of the colour dialog. A wrapper rather than a bare [ColorPreset]
/// because "no colour" is a real choice here, and popping a plain `null` is
/// indistinguishable from dismissing the dialog.
class ColorChoice {
  final ColorPreset? preset;
  const ColorChoice(this.preset);
}

/// Colour choice for a node; every node may also carry no accent at all.
class ColorPickerDialog extends StatelessWidget {
  final ColorPreset? selected;

  const ColorPickerDialog({super.key, this.selected});

  static Future<ColorChoice?> show(
    BuildContext context, {
    ColorPreset? selected,
  }) {
    return showDialog<ColorChoice>(
      context: context,
      builder: (_) => ColorPickerDialog(selected: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Choose Color'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(const ColorChoice(null)),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected == null ? Colors.black : Colors.grey,
                    width: selected == null ? 3 : 1,
                  ),
                ),
                child: Icon(Icons.block, size: 16, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 12),
              const Text('No colour'),
            ],
          ),
        ),
        for (final preset in ColorPreset.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ColorChoice(preset)),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(preset.colorValue),
                    shape: BoxShape.circle,
                    border: preset == selected
                        ? Border.all(color: Colors.black, width: 3)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Text(preset.label),
              ],
            ),
          ),
      ],
    );
  }
}
