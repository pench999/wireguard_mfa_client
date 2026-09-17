import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wireguard_mfa_client/src/models/mfa_session.dart';
import 'package:wireguard_mfa_client/src/services/mfa_api.dart';

void main() {
  test('creates a client session', () async {
    final api = MfaApi(
      client: MockClient((request) async {
        expect(request.url.path, '/api/client/v1/sessions/');
        return http.Response(
          '{"session_id":"session-1","browser_url":"https://vpn.example.com/client/connect/token/","poll_token":"poll-secret","expires_at":"2026-09-17T03:00:00Z"}',
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final session = await api.createSession(
      Uri.parse('https://vpn.example.com'),
      '123e4567-e89b-12d3-a456-426614174000',
    );

    expect(session.id, 'session-1');
    expect(session.pollToken, 'poll-secret');
    api.close();
  });

  test('parses unlocked status and sends bearer token', () async {
    final api = MfaApi(
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer poll-secret');
        return http.Response(
          '{"status":"unlocked","expires_at":"2026-09-17T03:00:00Z","unlocked_until":"2026-09-17T03:30:00Z"}',
          200,
        );
      }),
    );
    final session = MfaSession(
      id: 'session-1',
      browserUrl: Uri.parse('https://vpn.example.com/client/connect/token/'),
      pollToken: 'poll-secret',
      expiresAt: DateTime.utc(2026, 9, 17, 3),
    );

    final status = await api.getStatus(
      Uri.parse('https://vpn.example.com'),
      session,
    );

    expect(status.status, MfaSessionStatus.unlocked);
    expect(status.unlockedUntil, DateTime.utc(2026, 9, 17, 3, 30));
    api.close();
  });
}
