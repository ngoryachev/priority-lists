import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/services/auth_service.dart';
import 'domain/repositories/current_role_repository.dart';
import 'domain/repositories/last_node_repository.dart';
import 'domain/repositories/priority_node_repository.dart';
import 'presentation/view_models/auth_view_model.dart';
import 'presentation/view_models/filter_view_model.dart';
import 'presentation/view_models/last_node_view_model.dart';
import 'presentation/view_models/role_view_model.dart';
import 'presentation/widgets/auth_gate.dart';

class PriorityListsApp extends StatelessWidget {
  final PriorityNodeRepository localRepository;
  final AuthService authService;

  /// Where the current-role marker is kept. Optional: without it the selector
  /// still works, it just forgets the pick when the process ends.
  final CurrentRoleRepository? currentRoleRepository;

  /// Where the last opened node is kept. Optional: without it every launch
  /// opens at the root, which is the behaviour the app shipped with.
  final LastNodeRepository? lastNodeRepository;

  const PriorityListsApp({
    super.key,
    required this.localRepository,
    required this.authService,
    this.currentRoleRepository,
    this.lastNodeRepository,
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
        ChangeNotifierProvider(
          create: (_) => RoleViewModel(repository: currentRoleRepository),
        ),
        // Above the MaterialApp, like the role marker: the user id is read
        // per write, so the same instance serves whoever signs in next.
        Provider<LastNodeViewModel>(
          create: (_) => LastNodeViewModel(
            repository: lastNodeRepository,
            currentUserId: () => authService.currentUser?.id,
          ),
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
