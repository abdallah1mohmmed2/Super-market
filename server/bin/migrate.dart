import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';

/// Applies complete migration files with checksum tracking and an advisory lock.
Future<void> main() async {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty)
    throw ArgumentError('DATABASE_URL is required');
  final connection = await Connection.openFromUrl(url);
  try {
    await connection.execute("SELECT pg_advisory_lock(87139001)");
    await connection.execute(
      'CREATE TABLE IF NOT EXISTS schema_migrations(name text PRIMARY KEY,checksum text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now())',
    );
    final files =
        Directory('migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final sql = await file.readAsString();
      final checksum = sha256.convert(utf8.encode(sql)).toString();
      final existing = await connection.execute(
        Sql.named('SELECT checksum FROM schema_migrations WHERE name=@name'),
        parameters: {'name': name},
      );
      if (existing.isNotEmpty) {
        if (existing.first[0] != checksum)
          throw StateError('Migration checksum mismatch: $name');
        continue;
      }
      // The file already supplies BEGIN/COMMIT. Tracking is inserted before COMMIT.
      if (!sql.trimRight().endsWith('COMMIT;'))
        throw StateError('Migration must end with COMMIT: $name');
      final safeName = name.replaceAll("'", "''");
      final body = sql.trimRight().substring(
        0,
        sql.trimRight().length - 'COMMIT;'.length,
      );
      await connection.execute(
        "${body}INSERT INTO schema_migrations(name,checksum) VALUES('$safeName','$checksum'); COMMIT;",
        queryMode: QueryMode.simple,
      );
      stdout.writeln('Applied $name');
    }
  } finally {
    await connection.close();
  }
}
