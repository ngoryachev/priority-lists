import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/services/auth_service.dart';
import 'domain/repositories/priority_list_repository.dart';
import 'presentation/view_models/auth_view_model.dart';
import 'presentation/widgets/auth_gate.dart';

class PriorityListsApp extends StatelessWidget {
  final PriorityListRepository localRepository;
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
