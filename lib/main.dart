import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/env.dart';
import 'data/repositories/local_priority_list_repository.dart';
import 'data/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  final appDir = await getApplicationDocumentsDirectory();
  final localRepository = LocalPriorityListRepository(
    filePath: '${appDir.path}/priority_lists.json',
  );

  final client = Supabase.instance.client;
  final authService = AuthService(client);

  runApp(PriorityListsApp(
    localRepository: localRepository,
    authService: authService,
  ));
}
