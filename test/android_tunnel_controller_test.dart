import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wireguard_mfa_client/src/services/tunnel_controller_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jp.co.fairway.wgmfa/tunnel');
  const controller = AndroidTunnelController();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('maps persisted configuration state returned by Android', () async {
    for (final entry in {
      'running': TunnelState.running,
      'stopped': TunnelState.stopped,
      'notInstalled': TunnelState.notInstalled,
    }.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'state');
            expect(call.arguments, 'android_peer');
            return entry.key;
          });
      expect(await controller.getState('android_peer'), entry.value);
    }
  });

  test('preserves Android VPN permission denial', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'vpn_permission_denied');
        });
    await expectLater(
      controller.start('android_peer'),
      throwsA(
        isA<TunnelException>().having(
          (e) => e.code,
          'code',
          'vpn_permission_denied',
        ),
      ),
    );
  });

  test('passes the expiry deadline to native Android', () async {
    final deadline = DateTime.utc(2026, 10, 7, 12);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'start');
          expect(call.arguments, {
            'name': 'android_peer',
            'expiresAt': deadline.millisecondsSinceEpoch,
          });
          return null;
        });
    await controller.startAuthorized('android_peer', deadline);
  });

  test('disconnect lock mode passes no native deadline', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect((call.arguments as Map)['expiresAt'], isNull);
          return null;
        });
    await controller.startAuthorized('android_peer', null);
  });
}
