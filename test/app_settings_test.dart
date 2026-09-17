import 'package:flutter_test/flutter_test.dart';
import 'package:wireguard_mfa_client/src/models/app_settings.dart';

void main() {
  test('accepts a valid HTTPS configuration', () {
    const settings = AppSettings(
      serverUrl: 'https://vpn.example.com',
      peerUuid: '123e4567-e89b-12d3-a456-426614174000',
      tunnelName: 'office-wg',
    );
    expect(settings.validate(), isNull);
  });

  test('rejects an invalid peer UUID', () {
    const settings = AppSettings(
      serverUrl: 'https://vpn.example.com',
      peerUuid: 'peer-1',
      tunnelName: 'office-wg',
    );
    expect(settings.validate(), contains('peer UUID'));
  });
}
