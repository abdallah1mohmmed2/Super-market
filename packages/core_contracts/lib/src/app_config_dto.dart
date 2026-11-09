/// Version gates, branch-neutral report defaults and feature flags.
class AppConfigDto {
  final String minimumVersion;
  final String latestVersion;
  final String country;
  final String supermarketName;
  final Map<String, bool> featureFlags;

  /// Creates deployment-provided configuration without business seed data.
  const AppConfigDto({
    this.minimumVersion = '0.1.0',
    this.latestVersion = '0.1.0',
    this.country = 'الجمهورية اليمنية',
    this.supermarketName = 'السوبر ماركت',
    this.featureFlags = const {'catalog': true},
  });

  /// Decodes application configuration.
  factory AppConfigDto.fromJson(Map<String, dynamic> j) => AppConfigDto(
    minimumVersion: j['minimumVersion'] as String,
    latestVersion: j['latestVersion'] as String,
    country: j['country'] as String,
    supermarketName: j['supermarketName'] as String,
    featureFlags: Map<String, bool>.from(j['featureFlags'] as Map),
  );

  /// Serializes deployment configuration.
  Map<String, dynamic> toJson() => {
    'minimumVersion': minimumVersion,
    'latestVersion': latestVersion,
    'country': country,
    'supermarketName': supermarketName,
    'featureFlags': featureFlags,
  };
}
