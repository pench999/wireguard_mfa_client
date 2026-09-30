import 'package:flutter_test/flutter_test.dart';
import 'package:wireguard_mfa_client/src/controllers/vpn_controller.dart';
import 'package:wireguard_mfa_client/src/models/app_settings.dart';
import 'package:wireguard_mfa_client/src/models/device_identity.dart';
import 'package:wireguard_mfa_client/src/services/device_identity_repository.dart';
import 'package:wireguard_mfa_client/src/services/mfa_api.dart';
import 'package:wireguard_mfa_client/src/services/tunnel_controller_base.dart';

const _settings = AppSettings(
  serverUrl: 'https://vpn.example.com',
  peerUuid: '123e4567-e89b-42d3-a456-426614174000',
  tunnelName: 'office',
);

void main() {
  test('initialize requires provisioning when the tunnel is missing', () async {
    final controller = _controller(_FakeTunnel(TunnelState.notInstalled));

    final installed = await controller.initialize(_settings);

    expect(installed, isFalse);
    expect(controller.errorMessage, contains(r'WireGuardTunnel$office'));
    controller.dispose();
  });

  test('suspend stops the tunnel and returns to idle', () async {
    final tunnel = _FakeTunnel(TunnelState.running);
    final controller = _controller(tunnel);

    await controller.initialize(_settings);
    expect(controller.isConnected, isTrue);

    await controller.handleSuspend(_settings);

    expect(tunnel.stopCalls, 1);
    expect(tunnel.state, TunnelState.stopped);
    expect(controller.phase, ConnectionPhase.idle);
    expect(controller.message, 'スリープのため切断しました');
    controller.dispose();
  });

  test('resume stops a tunnel that remained active and requires MFA', () async {
    final tunnel = _FakeTunnel(TunnelState.running);
    final controller = _controller(tunnel);

    await controller.handleResume(_settings);

    expect(tunnel.stopCalls, 1);
    expect(tunnel.state, TunnelState.stopped);
    expect(controller.phase, ConnectionPhase.idle);
    expect(controller.message, contains('再接続にはMFA認証が必要'));
    controller.dispose();
  });

  test('resume leaves an already stopped tunnel stopped', () async {
    final tunnel = _FakeTunnel(TunnelState.stopped);
    final controller = _controller(tunnel);

    await controller.handleResume(_settings);

    expect(tunnel.stopCalls, 0);
    expect(controller.phase, ConnectionPhase.idle);
    controller.dispose();
  });
}

VpnController _controller(_FakeTunnel tunnel) => VpnController(
  api: MfaApi(),
  tunnel: tunnel,
  deviceIdentityRepository: _FakeDeviceIdentityRepository(),
);

class _FakeTunnel implements TunnelController {
  _FakeTunnel(this.state);

  TunnelState state;
  int stopCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<TunnelState> getState(String tunnelName) async => state;

  @override
  Future<void> start(String tunnelName) async {
    state = TunnelState.running;
  }

  @override
  Future<void> stop(String tunnelName) async {
    stopCalls++;
    state = TunnelState.stopped;
  }
}

class _FakeDeviceIdentityRepository implements DeviceIdentityRepository {
  @override
  Future<DeviceIdentity> loadOrCreate() async => const DeviceIdentity(
    id: '123e4567-e89b-42d3-a456-426614174111',
    token: 'test-token',
    name: 'TEST-PC',
  );
}
