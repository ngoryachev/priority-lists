import 'package:flutter/material.dart';

import '../../domain/models/priority.dart';
import 'priority_picker_widget.dart';

class ItemFormResult {
  final String title;
  final String description;
  final Priority priority;

  ItemFormResult({
    required this.title,
    required this.description,
    required this.priority,
  });
}

class ItemFormDialog extends StatefulWidget {
  final String? initialTitle;
  final String? initialDescription;
  final Priority initialPriority;

  const ItemFormDialog({
    super.key,
    this.initialTitle,
    this.initialDescription,
    this.initialPriority = Priority.medium,
  });

  @override
  State<ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<ItemFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late Priority _selectedPriority;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _descriptionController =
        TextEditingController(text: widget.initialDescription ?? '');
    _selectedPriority = widget.initialPriority;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialTitle != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Item' : 'New Item'),
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
                maxLength: 200,
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
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(
                ItemFormResult(
                  title: _titleController.text.trim(),
                  description: _descriptionController.text.trim(),
                  priority: _selectedPriority,
                ),
              );
            }
          },
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
