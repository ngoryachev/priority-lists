import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/services/auth_service.dart';
import 'domain/repositories/priority_node_repository.dart';
import 'presentation/view_models/auth_view_model.dart';
import 'presentation/view_models/filter_view_model.dart';
import 'presentation/widgets/auth_gate.dart';

class PriorityListsApp extends StatelessWidget {
  final PriorityNodeRepository localRepository;
  final AuthService authService;

  const PriorityListsApp({
    super.key,
    required this.localRepository,
    required this.authService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(authService),
        ),
        ChangeNotifierProvider(
          create: (_) => FilterViewModel(),
        ),
        Provider<AuthService>.value(value: authService),
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
        home: AuthGate(localRepository: localRepository),
      ),
    );
  }
}
