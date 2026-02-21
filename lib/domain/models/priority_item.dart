import 'priority.dart';

class PriorityItem {
  final String id;
  final String title;
  final String description;
  final Priority priority;
  final DateTime createdAt;
  final DateTime updatedAt;

  PriorityItem({
    required this.id,
    required this.title,
    this.description = '',
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
  }) {
    if (title.isEmpty) {
      throw ArgumentError('Item title must not be empty');
    }
    if (title.length > 200) {
      throw ArgumentError('Item title must not exceed 200 characters');
    }
  }

  PriorityItem copyWith({
    String? title,
    String? description,
    Priority? priority,
    DateTime? updatedAt,
  }) {
    return PriorityItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PriorityItem && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
