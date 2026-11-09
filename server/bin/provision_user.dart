import 'dart:io';
import 'package:postgres/postgres.dart';

/// Explicit operator provisioning; login itself never assigns administrative roles.
Future<void> main(List<String> args) async {
  if (args.length != 4)
    throw ArgumentError(
      'Usage: dart run bin/provision_user.dart FIREBASE_UID DISPLAY_NAME BRANCH_NAME ROLE_CODE',
    );
  final url = Platform.environment['DATABASE_URL'];
  if (url == null) throw ArgumentError('DATABASE_URL is required');
  final db = await Connection.openFromUrl(url);
  try {
    await db.runTx((tx) async {
      await tx.execute('SELECT pg_advisory_xact_lock(87139002)');
      final role = await tx.execute(
        Sql.named(
          'SELECT id FROM roles WHERE code=@code AND deleted_at IS NULL',
        ),
        parameters: {'code': args[3]},
      );
      if (role.length != 1) throw ArgumentError('Unknown role');
      final branches = await tx.execute(
        Sql.named(
          'SELECT id FROM branches WHERE name=@name AND deleted_at IS NULL',
        ),
        parameters: {'name': args[2]},
      );
      if (branches.length > 1) throw StateError('Ambiguous branch name');
      final branchId = branches.isEmpty
          ? (await tx.execute(
              Sql.named(
                'INSERT INTO branches(name) VALUES(@name) RETURNING id',
              ),
              parameters: {'name': args[2]},
            )).first[0]
          : branches.first[0];
      await tx.execute(
        Sql.named(
          'INSERT INTO users(firebase_uid,display_name,branch_id,role_id) VALUES(@uid,@name,@branch,@role)',
        ),
        parameters: {
          'uid': args[0],
          'name': args[1],
          'branch': branchId,
          'role': role.first[0],
        },
      );
    });
    stdout.writeln('User provisioned successfully');
  } finally {
    await db.close();
  }
}
