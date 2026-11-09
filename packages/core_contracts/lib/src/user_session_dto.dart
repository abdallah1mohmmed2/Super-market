/// Non-secret cached session data; it cannot authorize HTTP requests itself.
class UserSessionDto {
  final String userId;
  final String firebaseUid;
  final String displayName;
  final String branchId;
  final String branchName;
  final String role;
  final List<String> permissions;

  /// Constructs one explicitly provisioned user's session.
  UserSessionDto({
    required this.userId,
    required this.firebaseUid,
    required this.displayName,
    required this.branchId,
    required this.branchName,
    required this.role,
    required List<String> permissions,
  }) : permissions = List.unmodifiable(permissions);

  /// Decodes the server's session.
  factory UserSessionDto.fromJson(Map<String, dynamic> j) => UserSessionDto(
    userId: j['userId'] as String,
    firebaseUid: j['firebaseUid'] as String,
    displayName: j['displayName'] as String,
    branchId: j['branchId'] as String,
    branchName: j['branchName'] as String,
    role: j['role'] as String,
    permissions: (j['permissions'] as List).cast<String>(),
  );

  /// Serializes only non-secret authorization context.
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'firebaseUid': firebaseUid,
    'displayName': displayName,
    'branchId': branchId,
    'branchName': branchName,
    'role': role,
    'permissions': permissions,
  };
}
