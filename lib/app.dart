import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'domain/repositories/priority_list_repository.dart';
import 'presentation/screens/lists_overview_screen.dart';
import 'presentation/view_models/lists_overview_view_model.dart';

class PriorityListsApp extends StatelessWidget {
  final PriorityListRepository repository;

  const PriorityListsApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<PriorityListRepository>.value(value: repository),
        ChangeNotifierProvider(
          create: (_) => ListsOverviewViewModel(repository),
        ),
      ],
      child: MaterialApp(
        title: 'Priority Lists',
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const ListsOverviewScreen(),
      ),
    );
  }
}
