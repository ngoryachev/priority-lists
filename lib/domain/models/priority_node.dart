import 'color_preset.dart';
import 'priority.dart';

/// A single node of the priority tree.
///
/// Root nodes ([parentId] == null) are what used to be "lists" and everything
/// below them what used to be "items" — but there is no type distinction any
/// more: every node carries a title, a description and a priority, and every
/// node can hold children at any depth.
class PriorityNode {
  static const int maxTitleLength = 200;

  final String id;

  /// Parent node, or null when this node sits at the top level.
  final String? parentId;

  final String title;
  final String description;
  final Priority priority;

  /// Optional accent colour. Null means "inherit from the ancestor chain".
  final ColorPreset? colorPreset;

  final DateTime createdAt;
  final DateTime updatedAt;

  PriorityNode({
    required this.id,
    this.parentId,
    required this.title,
    this.description = '',
    required this.priority,
    this.colorPreset,
    required this.createdAt,
    required this.updatedAt,
  }) {
    if (title.isEmpty) {
      throw ArgumentError('Node title must not be empty');
    }
    if (title.length > maxTitleLength) {
      throw ArgumentError(
        'Node title must not exceed $maxTitleLength characters',
      );
    }
    if (parentId == id) {
      throw ArgumentError('Node cannot be its own parent');
    }
  }

  bool get isRoot => parentId == null;

  /// [clearColorPreset] exists because [colorPreset] is nullable: passing null
  /// means "leave it alone", so dropping the colour needs its own flag.
  PriorityNode copyWith({
    String? title,
    String? description,
    Priority? priority,
    ColorPreset? colorPreset,
    bool clearColorPreset = false,
    DateTime? updatedAt,
  }) {
    return PriorityNode(
      id: id,
      parentId: parentId,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      colorPreset: clearColorPreset ? null : (colorPreset ?? this.colorPreset),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Re-parents the node. Separate from [copyWith] because `null` is a
  /// meaningful destination here (the top level), which a nullable named
  /// parameter cannot express.
  PriorityNode withParent(String? newParentId, {DateTime? updatedAt}) {
    return PriorityNode(
      id: id,
      parentId: newParentId,
      title: title,
      description: description,
      priority: priority,
      colorPreset: colorPreset,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PriorityNode && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
