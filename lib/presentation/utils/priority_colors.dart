import 'package:flutter/material.dart';

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
