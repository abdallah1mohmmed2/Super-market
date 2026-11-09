import 'dart:io';
import 'package:core_contracts/core_contracts.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:supermarket_server/core/application.dart';
import 'package:supermarket_server/core/server_config.dart';
import 'package:supermarket_server/features/auth_users/data/in_memory_user_repository.dart';
import 'package:supermarket_server/features/auth_users/data/postgres_user_repository.dart';
import 'package:supermarket_server/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:supermarket_server/features/catalog/data/postgres_catalog_repository.dart';
import 'package:supermarket_server/infrastructure/firebase/firebase_auth_verifier.dart';

/// Composes production adapters and shuts down resources on termination.
Future<void> main() async {
  final env = Platform.environment;
  final config = ServerConfig(env);
  final client = http.Client();
  final pool = config.inMemory ? null : Pool.withUrl(config.databaseUrl!);
  final developmentUsers = <UserSessionDto>[];
  if (config.inMemory && (env['DEV_FIREBASE_UID'] ?? '').isNotEmpty) {
    developmentUsers.add(
      UserSessionDto(
        userId: '10000000-0000-4000-8000-000000000001',
        firebaseUid: env['DEV_FIREBASE_UID']!,
        displayName: 'حساب تطوير محلي',
        branchId: '20000000-0000-4000-8000-000000000001',
        branchName: 'فرع تطوير محلي',
        role: 'ADMIN',
        permissions: ['catalog.read', 'catalog.write', 'reports.cost.view'],
      ),
    );
  }
  final handler = createApplication(
    verifier: FirebaseAuthVerifier(config.projectId, client),
    users: pool == null
        ? InMemoryUserRepository(developmentUsers)
        : PostgresUserRepository(pool),
    catalog: pool == null
        ? InMemoryCatalogRepository()
        : PostgresCatalogRepository(pool),
    config: AppConfigDto(
      country: env['REPORT_COUNTRY'] ?? 'الجمهورية اليمنية',
      supermarketName: env['SUPERMARKET_NAME'] ?? 'السوبر ماركت',
    ),
    corsOrigins: config.corsOrigins,
    logger: stdout.writeln,
  );
  final server = await io.serve(handler, config.host, config.port);
  stdout.writeln(
    'Listening on ${server.address.host}:${server.port}; storage=${config.inMemory ? 'memory' : 'postgres'}',
  );
  var stopping = false;
  Future<void> stop(ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    await server.close(force: false);
    await pool?.close();
    client.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(stop);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(stop);
}
