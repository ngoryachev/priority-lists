import '../../domain/models/color_preset.dart';
import '../../domain/models/node_mark.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_node.dart';

/// JSON shape of a single tree node, used by the local file repository.
class PriorityNodeDto {
  final String id;
  final String? parentId;
  final String title;
  final String description;
  final int priority;
  final int position;
  final int? colorValue;

  /// Stored [NodeMark.value], or null for an unmarked node.
  final String? mark;

  final String createdAt;
  final String updatedAt;

  PriorityNodeDto({
    required this.id,
    required this.parentId,
    required this.title,
    required this.description,
    required this.priority,
    required this.position,
    required this.colorValue,
    this.mark,
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
      // Files written before manual ordering carry no position; 0 leaves them
      // sorted by age, exactly as they were.
      position: (json['position'] as int?) ?? 0,
      colorValue: json['colorValue'] as int?,
      // Files written before marks existed carry no key at all, which reads
      // as unmarked — the same tolerance as 'position' and 'colorValue'.
      mark: json['mark'] as String?,
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
      'position': position,
      'colorValue': colorValue,
      'mark': mark,
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
      position: node.position,
      colorValue: node.colorPreset?.colorValue,
      mark: node.mark?.value,
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
      position: position,
      colorPreset: ColorPreset.tryFromColorValue(colorValue),
      mark: NodeMark.tryFromValue(mark),
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }
}
