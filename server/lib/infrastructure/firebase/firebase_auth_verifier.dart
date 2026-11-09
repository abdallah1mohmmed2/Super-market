import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import '../../core/domain_failure.dart';
import '../../features/auth_users/domain/auth_verifier.dart';

/// Verifies Firebase RS256 signatures and claims against cached Google JWKs.
class FirebaseAuthVerifier implements AuthVerifier {
  final String projectId;
  final http.Client client;
  final DateTime Function() now;
  Map<String, dynamic> _keys = {};
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _refreshing;

  /// Injects the trusted project, an HTTP client and a testable clock.
  FirebaseAuthVerifier(
    this.projectId,
    this.client, {
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;

  BigInt _integer(String value) => BigInt.parse(
    base64Url
        .decode(base64Url.normalize(value))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    radix: 16,
  );

  Future<void> _refresh() async {
    if (_refreshing != null) return _refreshing;
    final pending = _fetchKeys();
    _refreshing = pending;
    try {
      await pending;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _fetchKeys() async {
    try {
      final r = await client
          .get(
            Uri.parse(
              'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) throw const FormatException();
      final keys = (jsonDecode(r.body) as Map<String, dynamic>)['keys'] as List;
      final next = <String, dynamic>{
        for (final k in keys) (k as Map<String, dynamic>)['kid'] as String: k,
      };
      if (next.isEmpty) throw const FormatException();
      final seconds =
          int.tryParse(
            RegExp(
                  r'max-age=(\d+)',
                ).firstMatch(r.headers['cache-control'] ?? '')?.group(1) ??
                '300',
          ) ??
          300;
      _keys = next;
      _lastRefresh = now();
      _expires = now().add(Duration(seconds: seconds.clamp(0, 21600)));
    } catch (_) {
      throw const DomainFailure('AUTH_UNAVAILABLE', 'تعذر تحديث مفاتيح التحقق');
    }
  }

  /// Rejects altered signatures, wrong project claims, expired or future tokens.
  @override
  Future<String> verify(String token) async {
    try {
      if (token.length > 16384) throw const FormatException();
      final parts = token.split('.');
      if (parts.length != 3) throw const FormatException();
      final header =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
              )
              as Map<String, dynamic>;
      if (header['alg'] != 'RS256' || header['kid'] is! String)
        throw const FormatException();
      if (!now().isBefore(_expires)) await _refresh();
      if (!_keys.containsKey(header['kid']) &&
          now().difference(_lastRefresh) >= const Duration(minutes: 1))
        await _refresh();
      final jwk = _keys[header['kid']] as Map<String, dynamic>?;
      if (jwk == null || jwk['kty'] != 'RSA') throw const FormatException();
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
        ..init(
          false,
          PublicKeyParameter<RSAPublicKey>(
            RSAPublicKey(
              _integer(jwk['n'] as String),
              _integer(jwk['e'] as String),
            ),
          ),
        );
      if (!signer.verifySignature(
        Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
        RSASignature(base64Url.decode(base64Url.normalize(parts[2]))),
      ))
        throw const FormatException();
      final c =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final seconds = now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (c['aud'] != projectId ||
          c['iss'] != 'https://securetoken.google.com/$projectId' ||
          c['sub'] is! String ||
          (c['sub'] as String).isEmpty ||
          (c['sub'] as String).length > 128 ||
          c['exp'] is! int ||
          (c['exp'] as int) <= seconds ||
          c['iat'] is! int ||
          (c['iat'] as int) > seconds ||
          (c['iat'] as int) < 0 ||
          c['auth_time'] is! int ||
          (c['auth_time'] as int) > seconds ||
          (c['auth_time'] as int) < 0)
        throw const FormatException();
      return c['sub'] as String;
    } on DomainFailure {
      rethrow;
    } catch (_) {
      throw const DomainFailure(
        'UNAUTHENTICATED',
        'رمز الدخول غير صالح أو منتهي',
      );
    }
  }
}
