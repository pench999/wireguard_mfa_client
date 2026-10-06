import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wireguard_mfa_client/src/models/provisioning_session.dart';
import 'package:wireguard_mfa_client/src/services/mfa_api.dart';

void main() {
  final server = Uri.parse('https://vpn.example.com');
  final session = ProvisioningSession(
    id: 'test-session',
    browserUrl: server,
    pollToken: 'test-token',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );

  test('status recovers after a transient DNS transport failure', () async {
    var requests = 0;
    final api = MfaApi(
      client: MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (requests == 1) throw http.ClientException('Failed host lookup');
        return http.Response('{"status":"authorized"}', 200);
      }),
    );
    addTearDown(api.close);
    expect(
      (await api.getProvisioningStatus(server, session)).status,
      'authorized',
    );
    expect(requests, 2);
  });

  test('persistent transport failures stop after three requests', () async {
    var requests = 0;
    final api = MfaApi(
      client: MockClient((request) async {
        requests++;
        throw http.ClientException('Failed host lookup');
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.getProvisioningStatus(server, session),
      throwsA(
        isA<MfaApiException>().having(
          (e) => e.code,
          'code',
          'network_unavailable',
        ),
      ),
    );
    expect(requests, 3);
  });

  test('authorization failures are not retried', () async {
    var requests = 0;
    final api = MfaApi(
      client: MockClient((request) async {
        requests++;
        return http.Response('{"error":"unauthorized"}', 401);
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.getProvisioningStatus(server, session),
      throwsA(
        isA<MfaApiException>().having((e) => e.code, 'code', 'unauthorized'),
      ),
    );
    expect(requests, 1);
  });
}
