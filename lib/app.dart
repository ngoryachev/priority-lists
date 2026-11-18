import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/services/auth_service.dart';
import 'domain/repositories/card_page_repository.dart';
import 'domain/repositories/last_node_repository.dart';
import 'domain/repositories/priority_node_repository.dart';
import 'presentation/view_models/auth_view_model.dart';
import 'presentation/view_models/card_page_view_model.dart';
import 'presentation/view_models/filter_view_model.dart';
import 'presentation/view_models/last_node_view_model.dart';
import 'presentation/widgets/auth_gate.dart';

class PriorityListsApp extends StatelessWidget {
  final PriorityNodeRepository localRepository;
  final AuthService authService;

  /// Where the last opened node is kept. Optional: without it every launch
  /// opens at the root, which is the behaviour the app shipped with.
  final LastNodeRepository? lastNodeRepository;

  /// Where the card pages are kept. Optional: without it a card remembers its
  /// page only for the lifetime of the process.
  final CardPageRepository? cardPageRepository;

  const PriorityListsApp({
    super.key,
    required this.localRepository,
    required this.authService,
    this.lastNodeRepository,
    this.cardPageRepository,
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
        // Above the MaterialApp: the user id is read per write, so the same
        // instance serves whoever signs in next.
        Provider<LastNodeViewModel>(
          create: (_) => LastNodeViewModel(
            repository: lastNodeRepository,
            currentUserId: () => authService.currentUser?.id,
          ),
        ),
        // Above the MaterialApp as well, so the page a card was swiped to
        // survives leaving its level and coming back.
        Provider<CardPageViewModel>(
          create: (_) => CardPageViewModel(repository: cardPageRepository),
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
