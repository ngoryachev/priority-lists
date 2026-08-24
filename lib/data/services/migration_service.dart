import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/repositories/priority_node_repository.dart';

class MigrationService {
  final PriorityNodeRepository localRepository;
  final PriorityNodeRepository remoteRepository;

  MigrationService({
    required this.localRepository,
    required this.remoteRepository,
  });

  Future<void> migrateIfNeeded() async {
    // No file system on web: the pre-auth repository is in-memory,
    // so there is never local data to migrate.
    if (kIsWeb) return;

    if (await _isMigrationCompleted()) return;

    final localNodes = await localRepository.getAllNodes();
    if (localNodes.isEmpty) {
      await _markMigrationCompleted();
      return;
    }

    final remoteNodes = await remoteRepository.getAllNodes();
    if (remoteNodes.isNotEmpty) {
      await _markMigrationCompleted();
      return;
    }

    await remoteRepository.saveNodes(localNodes);

    await _markMigrationCompleted();
  }

  Future<bool> _isMigrationCompleted() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/.migration_done').existsSync();
  }

  Future<void> _markMigrationCompleted() async {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/.migration_done').create();
  }
}
