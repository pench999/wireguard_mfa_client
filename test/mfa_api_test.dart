import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wireguard_mfa_client/src/models/mfa_session.dart';
import 'package:wireguard_mfa_client/src/models/provisioning_session.dart';
import 'package:wireguard_mfa_client/src/models/device_identity.dart';
import 'package:wireguard_mfa_client/src/services/mfa_api.dart';

void main() {
  const device = DeviceIdentity(
    id: '123e4567-e89b-42d3-a456-426614174111',
    token: 'device-token-abcdefghijklmnopqrstuvwxyz123456',
    name: 'TEST-PC',
  );

  test('creates a client session', () async {
    final api = MfaApi(
      client: MockClient((request) async {
        expect(request.url.path, '/api/client/v1/sessions/');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['device_id'], device.id);
        expect(body['device_token'], device.token);
        expect(body['device_name'], device.name);
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
      device,
    );

    expect(session.id, 'session-1');
    expect(session.pollToken, 'poll-secret');
    expect(
      session.browserUrl,
      Uri.parse('https://vpn.example.com/client/connect/token/'),
    );
    api.close();
  });

  test('pins browser URL to the configured HTTPS server', () async {
    final api = MfaApi(
      client: MockClient((request) async {
        return http.Response(
          '{"session_id":"session-1","browser_url":"http://internal-proxy/client/connect/token/?next=%2Fvpn%2F","poll_token":"poll-secret","expires_at":"2026-09-17T03:00:00Z"}',
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final session = await api.createSession(
      Uri.parse('https://vpn.example.com'),
      '123e4567-e89b-12d3-a456-426614174000',
      device,
    );

    expect(session.browserUrl.scheme, 'https');
    expect(session.browserUrl.host, 'vpn.example.com');
    expect(session.browserUrl.path, '/client/connect/token/');
    expect(session.browserUrl.query, 'next=%2Fvpn%2F');
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

  test('creates a provisioning session without a peer UUID', () async {
    final api = MfaApi(
      client: MockClient((request) async {
        expect(request.url.path, '/api/client/v1/provisioning/');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('peer_uuid'), isFalse);
        expect(body['device_id'], device.id);
        return http.Response(
          '{"session_id":"provision-1","browser_url":"http://proxy/client/provision/token/","poll_token":"provision-secret","expires_at":"2026-09-30T03:00:00Z"}',
          201,
        );
      }),
    );

    final session = await api.createProvisioningSession(
      Uri.parse('https://vpn.example.com'),
      device,
    );

    expect(
      session.browserUrl,
      Uri.parse('https://vpn.example.com/client/provision/token/'),
    );
    api.close();
  });

  test(
    'downloads the authorized configuration with its bearer token',
    () async {
      final api = MfaApi(
        client: MockClient((request) async {
          expect(
            request.url.path,
            '/api/client/v1/provisioning/provision-1/config/',
          );
          expect(request.headers['Authorization'], 'Bearer provision-secret');
          return http.Response(
            '{"peer_uuid":"123e4567-e89b-42d3-a456-426614174000","tunnel_name":"wgmfa_123e4567e89b","config":"[Interface]\\nPrivateKey = secret"}',
            200,
          );
        }),
      );
      final session = ProvisioningSession(
        id: 'provision-1',
        browserUrl: Uri.parse(
          'https://vpn.example.com/client/provision/token/',
        ),
        pollToken: 'provision-secret',
        expiresAt: DateTime.utc(2026, 9, 30, 3),
      );

      final config = await api.downloadProvisioningConfig(
        Uri.parse('https://vpn.example.com'),
        session,
      );

      expect(config.tunnelName, 'wgmfa_123e4567e89b');
      expect(config.config, contains('PrivateKey = secret'));
      api.close();
    },
  );
}
