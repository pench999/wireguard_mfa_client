import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wireguard_mfa_client/src/models/device_identity.dart';
import 'package:wireguard_mfa_client/src/services/mfa_api.dart';

void main() {
  const device = DeviceIdentity(
    id: 'device-id',
    token: 'device-token',
    name: 'Android',
  );
  for (final requestAppReturn in [true, false]) {
    test(
      'browser return flag applies to both flows: $requestAppReturn',
      () async {
        final api = MfaApi(
          requestAppReturn: requestAppReturn,
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'session_id': 'test-session',
                'browser_url':
                    'http://untrusted.example/connect/?existing=value',
                'poll_token': 'secret-token',
                'expires_at': '2030-01-01T00:00:00Z',
              }),
              201,
            ),
          ),
        );
        addTearDown(api.close);
        final server = Uri.parse('https://vpn.example.com');
        final provision = await api.createProvisioningSession(server, device);
        final connect = await api.createSession(server, 'test-peer', device);
        for (final url in [provision.browserUrl, connect.browserUrl]) {
          expect(url.origin, server.origin);
          expect(url.queryParameters['existing'], 'value');
          expect(
            url.queryParameters['return_to_app'],
            requestAppReturn ? 'android' : null,
          );
          expect(url.toString(), isNot(contains('secret-token')));
        }
      },
    );
  }
}
