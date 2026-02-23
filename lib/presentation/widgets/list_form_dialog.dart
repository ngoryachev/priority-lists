import 'package:flutter/material.dart';

import '../../domain/models/color_preset.dart';
import '../../domain/models/priority.dart';
import 'color_picker_dialog.dart';
import 'priority_picker_widget.dart';

class ListFormResult {
  final String name;
  final ColorPreset colorPreset;
  final Priority priority;

  ListFormResult({
    required this.name,
    required this.colorPreset,
    required this.priority,
  });
}

class ListFormDialog extends StatefulWidget {
  final String? initialName;
  final ColorPreset initialColor;
  final Priority initialPriority;

  const ListFormDialog({
    super.key,
    this.initialName,
    this.initialColor = ColorPreset.blue,
    this.initialPriority = Priority.medium,
  });

  @override
  State<ListFormDialog> createState() => _ListFormDialogState();
}

class _ListFormDialogState extends State<ListFormDialog> {
  late final TextEditingController _nameController;
  late ColorPreset _selectedColor;
  late Priority _selectedPriority;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _selectedColor = widget.initialColor;
    _selectedPriority = widget.initialPriority;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialName != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit List' : 'New List'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'List Name',
                border: OutlineInputBorder(),
              ),
              maxLength: 50,
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            const Text('Priority'),
            const SizedBox(height: 8),
            PriorityPickerWidget(
              selected: _selectedPriority,
              onChanged: (p) => setState(() => _selectedPriority = p),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final result = await showDialog<ColorPreset>(
                  context: context,
                  builder: (_) => ColorPickerDialog(selected: _selectedColor),
                );
                if (result != null) {
                  setState(() => _selectedColor = result);
                }
              },
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(_selectedColor.colorValue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _selectedColor.label,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right),
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
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(
                ListFormResult(
                  name: _nameController.text.trim(),
                  colorPreset: _selectedColor,
                  priority: _selectedPriority,
                ),
              );
            }
          },
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
