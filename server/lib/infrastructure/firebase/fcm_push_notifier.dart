import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../shared/domain/push_notifier.dart';

/// FCM HTTP v1 adapter using an injected server-side Google OAuth access token.
class FcmPushNotifier implements PushNotifier {
  final String projectId;
  final Future<String> Function() accessToken;
  final http.Client client;

  /// Keeps OAuth credentials outside feature and domain code.
  const FcmPushNotifier(this.projectId, this.accessToken, this.client);

  /// Delivers a data message or reports an external-service failure to the caller.
  @override
  Future<void> send(String token, Map<String, String> data) async {
    final r = await client
        .post(
          Uri.parse(
            'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
          ),
          headers: {
            'Authorization': 'Bearer ${await accessToken()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'message': {'token': token, 'data': data},
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode >= 300)
      throw StateError('FCM rejected notification (${r.statusCode})');
  }
}
