import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';
import 'package:supermarket_server/core/domain_failure.dart';
import 'package:supermarket_server/infrastructure/firebase/firebase_auth_verifier.dart';

void main() {
  final clock = DateTime.utc(2030, 1, 1);
  final now = clock.millisecondsSinceEpoch ~/ 1000;
  late RSAPrivateKey privateKey;
  late RSAPublicKey publicKey;
  String integer(BigInt n) {
    var hex = n.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    return base64Url
        .encode([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ])
        .replaceAll('=', '');
  }

  String token(Map<String, dynamic> changes, {String algorithm = 'RS256'}) {
    final header = base64Url
        .encode(utf8.encode(jsonEncode({'alg': algorithm, 'kid': 'fixture'})))
        .replaceAll('=', '');
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'aud': 'project-test',
              'iss': 'https://securetoken.google.com/project-test',
              'sub': 'uid',
              'exp': now + 3600,
              'iat': now - 60,
              'auth_time': now - 60,
              ...changes,
            }),
          ),
        )
        .replaceAll('=', '');
    final input = '$header.$payload';
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final signature = signer.generateSignature(
      Uint8List.fromList(utf8.encode(input)),
    );
    return '$input.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
  }

  setUpAll(() {
    // Deterministic fixture key, generated only inside the test process.
    final random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i + 1))));
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    privateKey = pair.privateKey as RSAPrivateKey;
    publicKey = pair.publicKey as RSAPublicKey;
  });
  test('verifies a signed token and caches trusted JWK keys', () async {
    var calls = 0;
    final verifier = FirebaseAuthVerifier(
      'project-test',
      MockClient((request) async {
        calls++;
        expect(request.url.host, 'www.googleapis.com');
        return http.Response(
          jsonEncode({
            'keys': [
              {
                'kid': 'fixture',
                'kty': 'RSA',
                'n': integer(publicKey.modulus!),
                'e': integer(publicKey.exponent!),
              },
            ],
          }),
          200,
          headers: {'cache-control': 'public,max-age=3600'},
        );
      }),
      clock: () => clock,
    );
    expect(await verifier.verify(token({})), 'uid');
    expect(await verifier.verify(token({})), 'uid');
    expect(calls, 1);
  });
  test(
    'rejects forged signatures, wrong claims, expired and unsigned tokens',
    () async {
      final verifier = FirebaseAuthVerifier(
        'project-test',
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'keys': [
                {
                  'kid': 'fixture',
                  'kty': 'RSA',
                  'n': integer(publicKey.modulus!),
                  'e': integer(publicKey.exponent!),
                },
              ],
            }),
            200,
          ),
        ),
        clock: () => clock,
      );
      for (final claims in [
        {'aud': 'other'},
        {'iss': 'https://evil.test'},
        {'sub': ''},
        {'exp': now},
        {'iat': now + 60},
        {'auth_time': now + 60},
      ]) {
        await expectLater(
          verifier.verify(token(claims)),
          throwsA(
            isA<DomainFailure>().having(
              (e) => e.code,
              'code',
              'UNAUTHENTICATED',
            ),
          ),
        );
      }
      final good = token({});
      final parts = good.split('.');
      parts[2] = 'A${parts[2].substring(1)}';
      await expectLater(
        verifier.verify(parts.join('.')),
        throwsA(isA<DomainFailure>()),
      );
      await expectLater(
        verifier.verify(token({}, algorithm: 'none')),
        throwsA(isA<DomainFailure>()),
      );
      await expectLater(
        verifier.verify('not-a-jwt'),
        throwsA(isA<DomainFailure>()),
      );
    },
  );
  test('key service failures do not authenticate a token', () async {
    final verifier = FirebaseAuthVerifier(
      'project-test',
      MockClient((_) async => http.Response('', 503)),
      clock: () => clock,
    );
    await expectLater(
      verifier.verify(token({})),
      throwsA(
        isA<DomainFailure>().having((e) => e.code, 'code', 'AUTH_UNAVAILABLE'),
      ),
    );
  });
}
