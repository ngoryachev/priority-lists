import 'package:flutter/material.dart';

import '../../domain/models/color_preset.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_node.dart';
import 'color_picker_dialog.dart';
import 'priority_picker_widget.dart';

class NodeFormResult {
  final String title;
  final String description;
  final Priority priority;
  final ColorPreset? colorPreset;

  NodeFormResult({
    required this.title,
    required this.description,
    required this.priority,
    required this.colorPreset,
  });
}

/// Create/edit form for any node in the tree — the same dialog whether the node
/// sits at the top level or ten levels down.
class NodeFormDialog extends StatefulWidget {
  final String? initialTitle;
  final String? initialDescription;
  final Priority initialPriority;
  final ColorPreset? initialColor;

  /// Name of the node the new child goes under, shown in the header so it is
  /// obvious which level is being added to. Null for the top level.
  final String? parentTitle;

  const NodeFormDialog({
    super.key,
    this.initialTitle,
    this.initialDescription,
    this.initialPriority = Priority.medium,
    this.initialColor,
    this.parentTitle,
  });

  @override
  State<NodeFormDialog> createState() => _NodeFormDialogState();
}

class _NodeFormDialogState extends State<NodeFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late Priority _selectedPriority;
  ColorPreset? _selectedColor;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _descriptionController =
        TextEditingController(text: widget.initialDescription ?? '');
    _selectedPriority = widget.initialPriority;
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.initialTitle != null;

  String get _dialogTitle {
    if (_isEditing) return 'Edit';
    final parent = widget.parentTitle;
    return parent == null ? 'New Top-Level Node' : 'New Node in "$parent"';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_dialogTitle),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                maxLength: PriorityNode.maxTitleLength,
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Title is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
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
                onTap: _pickColor,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _selectedColor == null
                            ? null
                            : Color(_selectedColor!.colorValue),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: _selectedColor == null
                          ? Icon(Icons.block, size: 18, color: Colors.grey.shade500)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _selectedColor?.label ?? 'No colour',
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  Future<void> _pickColor() async {
    final choice = await ColorPickerDialog.show(context, selected: _selectedColor);
    if (choice != null) {
      setState(() => _selectedColor = choice.preset);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      NodeFormResult(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _selectedPriority,
        colorPreset: _selectedColor,
      ),
    );
  }
}
