import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/supabase_priority_list_repository.dart';
import '../../data/services/migration_service.dart';
import '../../domain/repositories/priority_list_repository.dart';
import '../screens/lists_overview_screen.dart';
import '../screens/login_screen.dart';
import '../view_models/auth_view_model.dart';
import '../view_models/lists_overview_view_model.dart';

class AuthGate extends StatelessWidget {
  final PriorityListRepository localRepository;

  const AuthGate({super.key, required this.localRepository});

  @override
  Widget build(BuildContext context) {
    final authVm = context.watch<AuthViewModel>();

    if (!authVm.isAuthenticated) {
      return const LoginScreen();
    }

    final client = Supabase.instance.client;
    final supabaseRepository = SupabasePriorityListRepository(client);

    return _MigrationWrapper(
      localRepository: localRepository,
      supabaseRepository: supabaseRepository,
    );
  }
}

class _MigrationWrapper extends StatefulWidget {
  final PriorityListRepository localRepository;
  final SupabasePriorityListRepository supabaseRepository;

  const _MigrationWrapper({
    required this.localRepository,
    required this.supabaseRepository,
  });

  @override
  State<_MigrationWrapper> createState() => _MigrationWrapperState();
}

class _MigrationWrapperState extends State<_MigrationWrapper> {
  bool _migrating = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runMigration();
  }

  Future<void> _runMigration() async {
    try {
      final migrationService = MigrationService(
        localRepository: widget.localRepository,
        remoteRepository: widget.supabaseRepository,
      );
      await migrationService.migrateIfNeeded();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
      return;
    }
    if (mounted) {
      setState(() => _migrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Migration error: $_error'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _migrating = true;
                    });
                    _runMigration();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_migrating) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Syncing data...'),
            ],
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        Provider<PriorityListRepository>.value(
          value: widget.supabaseRepository,
        ),
        ChangeNotifierProvider(
          create: (_) => ListsOverviewViewModel(widget.supabaseRepository),
        ),
      ],
      child: const ListsOverviewScreen(),
    );
  }
}
