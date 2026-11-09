import 'package:core_contracts/core_contracts.dart';
import 'package:postgres/postgres.dart';
import '../domain/user_repository.dart';

/// Reads live role permissions and branch membership from PostgreSQL.
class PostgresUserRepository implements UserRepository {
  final Pool pool;

  /// Injects pooled SQL access at the infrastructure boundary.
  const PostgresUserRepository(this.pool);

  /// Resolves only enabled users, enabled roles and non-deleted branches.
  @override
  Future<UserSessionDto?> findByFirebaseUid(String uid) async {
    final rows = await pool.execute(
      Sql.named('''SELECT u.id::text,u.firebase_uid,u.display_name,
 u.branch_id::text,b.name,r.code,COALESCE(array_agg(rp.permission) FILTER(WHERE rp.permission IS NOT NULL),'{}')
 FROM users u JOIN branches b ON b.id=u.branch_id AND b.deleted_at IS NULL
 JOIN roles r ON r.id=u.role_id AND r.deleted_at IS NULL
 LEFT JOIN role_permissions rp ON rp.role_id=r.id AND rp.deleted_at IS NULL
 WHERE u.firebase_uid=@uid AND u.is_active AND u.deleted_at IS NULL
 GROUP BY u.id,b.name,r.code'''),
      parameters: {'uid': uid},
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return UserSessionDto(
      userId: r[0] as String,
      firebaseUid: r[1] as String,
      displayName: r[2] as String,
      branchId: r[3] as String,
      branchName: r[4] as String,
      role: r[5] as String,
      permissions: (r[6] as List).cast<String>(),
    );
  }
}
