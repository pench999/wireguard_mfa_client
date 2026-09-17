import 'dart:io';

import 'tunnel_controller_base.dart';

export 'tunnel_controller_base.dart';

TunnelController createTunnelController() => const WindowsTunnelController();

class WindowsTunnelController implements TunnelController {
  const WindowsTunnelController();

  @override
  bool get isSupported => Platform.isWindows;

  String get _scPath {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$systemRoot${Platform.pathSeparator}System32${Platform.pathSeparator}sc.exe';
  }

  String _serviceName(String tunnelName) => r'WireGuardTunnel$' + tunnelName;

  @override
  Future<TunnelState> getState(String tunnelName) async {
    if (!isSupported) return TunnelState.unsupported;
    final result = await Process.run(_scPath, [
      'query',
      _serviceName(tunnelName),
    ]);
    if (result.exitCode == 1060 ||
        (result.exitCode != 0 && result.stdout.toString().isEmpty)) {
      return TunnelState.notInstalled;
    }
    final match = RegExp(r'STATE\s*:\s*(\d+)')
        .firstMatch(result.stdout.toString());
    return switch (match?.group(1)) {
      '1' => TunnelState.stopped,
      '2' => TunnelState.starting,
      '3' => TunnelState.stopping,
      '4' => TunnelState.running,
      _ =>
        result.exitCode == 0 ? TunnelState.unknown : TunnelState.notInstalled,
    };
  }

  @override
  Future<void> start(String tunnelName) =>
      _changeState(tunnelName, 'start', TunnelState.running);

  @override
  Future<void> stop(String tunnelName) async {
    final current = await getState(tunnelName);
    if (current == TunnelState.stopped || current == TunnelState.notInstalled) {
      return;
    }
    await _changeState(tunnelName, 'stop', TunnelState.stopped);
  }

  Future<void> _changeState(
    String tunnelName,
    String command,
    TunnelState expected,
  ) async {
    if (!isSupported) throw const TunnelException('unsupported_platform');
    final result = await Process.run(_scPath, [
      command,
      _serviceName(tunnelName),
    ]);
    if (result.exitCode != 0 && await getState(tunnelName) != expected) {
      throw TunnelException(
        'service_${command}_failed',
        result.stderr.toString().trim(),
      );
    }
    for (var attempt = 0; attempt < 20; attempt++) {
      if (await getState(tunnelName) == expected) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TunnelException('service_${command}_timeout');
  }
}
