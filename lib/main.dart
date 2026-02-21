import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/repositories/local_priority_list_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appDir = await getApplicationDocumentsDirectory();
  final repository = LocalPriorityListRepository(
    filePath: '${appDir.path}/priority_lists.json',
  );

  runApp(PriorityListsApp(repository: repository));
}
