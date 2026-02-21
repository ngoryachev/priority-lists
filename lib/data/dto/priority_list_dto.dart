import '../../domain/models/color_preset.dart';
import '../../domain/models/priority_list.dart';
import 'priority_item_dto.dart';

class PriorityListDto {
  final String id;
  final String name;
  final int colorValue;
  final List<PriorityItemDto> items;
  final String createdAt;
  final String updatedAt;

  PriorityListDto({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PriorityListDto.fromJson(Map<String, dynamic> json) {
    return PriorityListDto(
      id: json['id'] as String,
      name: json['name'] as String,
      colorValue: json['colorValue'] as int,
      items: (json['items'] as List<dynamic>)
          .map((item) => PriorityItemDto.fromJson(item as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'colorValue': colorValue,
      'items': items.map((item) => item.toJson()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory PriorityListDto.fromEntity(PriorityList list) {
    return PriorityListDto(
      id: list.id,
      name: list.name,
      colorValue: list.colorPreset.colorValue,
      items: list.items.map((item) => PriorityItemDto.fromEntity(item)).toList(),
      createdAt: list.createdAt.toIso8601String(),
      updatedAt: list.updatedAt.toIso8601String(),
    );
  }

  PriorityList toEntity() {
    return PriorityList(
      id: id,
      name: name,
      colorPreset: ColorPreset.fromColorValue(colorValue),
      items: items.map((item) => item.toEntity()).toList(),
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }
}
