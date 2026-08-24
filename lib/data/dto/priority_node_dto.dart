import '../../domain/models/color_preset.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_node.dart';

/// JSON shape of a single tree node, used by the local file repository.
class PriorityNodeDto {
  final String id;
  final String? parentId;
  final String title;
  final String description;
  final int priority;
  final int? colorValue;
  final String createdAt;
  final String updatedAt;

  PriorityNodeDto({
    required this.id,
    required this.parentId,
    required this.title,
    required this.description,
    required this.priority,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PriorityNodeDto.fromJson(Map<String, dynamic> json) {
    return PriorityNodeDto(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      // Pre-nesting files stored a list's label under 'name'.
      title: (json['title'] ?? json['name']) as String,
      description: json['description'] as String? ?? '',
      priority: (json['priority'] as int?) ?? Priority.medium.value,
      colorValue: json['colorValue'] as int?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'title': title,
      'description': description,
      'priority': priority,
      'colorValue': colorValue,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory PriorityNodeDto.fromEntity(PriorityNode node) {
    return PriorityNodeDto(
      id: node.id,
      parentId: node.parentId,
      title: node.title,
      description: node.description,
      priority: node.priority.value,
      colorValue: node.colorPreset?.colorValue,
      createdAt: node.createdAt.toIso8601String(),
      updatedAt: node.updatedAt.toIso8601String(),
    );
  }

  PriorityNode toEntity() {
    return PriorityNode(
      id: id,
      parentId: parentId,
      title: title,
      description: description,
      priority: Priority.fromValue(priority),
      colorPreset: ColorPreset.tryFromColorValue(colorValue),
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }
}
