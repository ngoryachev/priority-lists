import 'color_preset.dart';
import 'priority.dart';
import 'priority_item.dart';

class PriorityList {
  final String id;
  final String name;
  final ColorPreset colorPreset;
  final Priority priority;
  final List<PriorityItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  PriorityList({
    required this.id,
    required this.name,
    required this.colorPreset,
    this.priority = Priority.medium,
    List<PriorityItem>? items,
    required this.createdAt,
    required this.updatedAt,
  }) : items = List.unmodifiable(items ?? []) {
    if (name.isEmpty) {
      throw ArgumentError('List name must not be empty');
    }
    if (name.length > 50) {
      throw ArgumentError('List name must not exceed 50 characters');
    }
  }

  List<PriorityItem> get sortedItems => List.of(items)
    ..sort((a, b) => a.priority.value.compareTo(b.priority.value));

  PriorityList addItem(PriorityItem item) {
    return copyWith(items: [...items, item]);
  }

  PriorityList updateItem(PriorityItem updated) {
    return copyWith(
      items: items.map((item) => item.id == updated.id ? updated : item).toList(),
    );
  }

  PriorityList removeItem(String itemId) {
    return copyWith(items: items.where((item) => item.id != itemId).toList());
  }

  PriorityList copyWith({
    String? name,
    ColorPreset? colorPreset,
    Priority? priority,
    List<PriorityItem>? items,
    DateTime? updatedAt,
  }) {
    return PriorityList(
      id: id,
      name: name ?? this.name,
      colorPreset: colorPreset ?? this.colorPreset,
      priority: priority ?? this.priority,
      items: items ?? this.items,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PriorityList && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
