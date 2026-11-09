/// Validated deployment settings; production can never fall back to memory.
class ServerConfig {
  final String projectId;
  final String? databaseUrl;
  final bool inMemory;
  final int port;
  final String host;
  final Set<String> corsOrigins;

  /// Builds settings from explicitly supplied environment variables.
  ServerConfig(Map<String, String> env)
    : projectId = env['FIREBASE_PROJECT_ID'] ?? '',
      databaseUrl = env['DATABASE_URL'],
      inMemory = env['CATALOG_STORAGE'] == 'memory',
      port = int.tryParse(env['PORT'] ?? '8080') ?? 8080,
      host = env['HOST'] ?? '127.0.0.1',
      corsOrigins = (env['CORS_ORIGINS'] ?? '')
          .split(',')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toSet() {
    if (projectId.isEmpty)
      throw ArgumentError('FIREBASE_PROJECT_ID is required');
    if (!inMemory && (databaseUrl == null || databaseUrl!.isEmpty))
      throw ArgumentError('DATABASE_URL is required');
    if (inMemory && env['APP_ENV'] == 'production')
      throw ArgumentError('Memory storage is forbidden in production');
    if (port < 1 || port > 65535) throw ArgumentError('PORT is invalid');
    if (corsOrigins.contains('*'))
      throw ArgumentError('CORS_ORIGINS must name explicit origins');
  }
}
