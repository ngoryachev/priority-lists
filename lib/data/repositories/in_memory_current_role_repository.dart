import '../../domain/models/role.dart';
import '../../domain/repositories/current_role_repository.dart';

/// Role storage for tests and for entry points without Supabase.
/// Lives only as long as the process does.
class InMemoryCurrentRoleRepository implements CurrentRoleRepository {
  Role? _role;

  @override
  Future<Role?> load() async => _role;

  @override
  Future<void> save(Role role) async => _role = role;
}
