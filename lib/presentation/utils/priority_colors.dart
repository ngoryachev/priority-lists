import 'package:flutter/material.dart';

import '../../domain/models/node_mark.dart';
import '../../domain/models/priority.dart';

/// Centralised mapping from [Priority] to its display colour.
Color priorityColor(Priority priority) {
  return switch (priority) {
    Priority.critical => Colors.red.shade400,
    Priority.high => Colors.orange.shade400,
    Priority.medium => Colors.blue.shade400,
    Priority.low => Colors.grey.shade400,
  };
}

/// Centralised mapping from [NodeMark] to its display colour — deliberately
/// nothing a priority uses, so a mark never reads as a fifth priority.
Color markColor(NodeMark mark) {
  return switch (mark) {
    NodeMark.flame => Colors.deepOrange.shade700,
    NodeMark.ice => Colors.lightBlue.shade700,
  };
}
