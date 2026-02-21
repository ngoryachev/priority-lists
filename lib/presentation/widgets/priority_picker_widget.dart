import 'package:flutter/material.dart';

import '../../domain/models/priority.dart';

class PriorityPickerWidget extends StatelessWidget {
  final Priority selected;
  final ValueChanged<Priority> onChanged;

  const PriorityPickerWidget({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Priority>(
      segments: Priority.values.map((p) {
        return ButtonSegment<Priority>(
          value: p,
          label: Text(p.label),
        );
      }).toList(),
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
