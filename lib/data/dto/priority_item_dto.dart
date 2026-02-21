import '../../domain/models/priority.dart';
import '../../domain/models/priority_item.dart';

class PriorityItemDto {
  final String id;
  final String title;
  final String description;
  final int priority;
  final String createdAt;
  final String updatedAt;

  PriorityItemDto({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PriorityItemDto.fromJson(Map<String, dynamic> json) {
    return PriorityItemDto(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      priority: json['priority'] as int,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'priority': priority,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory PriorityItemDto.fromEntity(PriorityItem item) {
    return PriorityItemDto(
      id: item.id,
      title: item.title,
      description: item.description,
      priority: item.priority.value,
      createdAt: item.createdAt.toIso8601String(),
      updatedAt: item.updatedAt.toIso8601String(),
    );
  }

  PriorityItem toEntity() {
    return PriorityItem(
      id: id,
      title: title,
      description: description,
      priority: Priority.fromValue(priority),
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }
}
