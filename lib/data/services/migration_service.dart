import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/repositories/priority_list_repository.dart';

class MigrationService {
  final PriorityListRepository localRepository;
  final PriorityListRepository remoteRepository;

  MigrationService({
    required this.localRepository,
    required this.remoteRepository,
  });

  Future<void> migrateIfNeeded() async {
    if (await _isMigrationCompleted()) return;

    final localLists = await localRepository.getAllLists();
    if (localLists.isEmpty) {
      await _markMigrationCompleted();
      return;
    }

    final remoteLists = await remoteRepository.getAllLists();
    if (remoteLists.isNotEmpty) {
      await _markMigrationCompleted();
      return;
    }

    for (final list in localLists) {
      await remoteRepository.saveList(list);
    }

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
