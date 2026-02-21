import 'package:flutter/material.dart';

import '../../domain/models/color_preset.dart';

class ColorPickerDialog extends StatelessWidget {
  final ColorPreset selected;

  const ColorPickerDialog({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Choose Color'),
      children: ColorPreset.values.map((preset) {
        return SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(preset),
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
        );
      }).toList(),
    );
  }
}
