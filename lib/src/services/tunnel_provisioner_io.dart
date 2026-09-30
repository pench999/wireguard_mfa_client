import 'dart:convert';
import 'dart:io';

Future<void> provisionTunnel(String tunnelName, String config) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Tunnel provisioning is only available on Windows.');
  }
  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  final script =
      '$executableDirectory${Platform.pathSeparator}installer'
      '${Platform.pathSeparator}provision_tunnel.ps1';
  if (!File(script).existsSync()) {
    throw StateError('初期設定スクリプトが見つかりません。アプリを再インストールしてください。');
  }
  final temporaryDirectory = await Directory.systemTemp.createTemp('wgmfa_');
  final temporaryConfig = File(
    '${temporaryDirectory.path}${Platform.pathSeparator}$tunnelName.conf',
  );
  try {
    await temporaryConfig.writeAsString(config, flush: true);
    final domain = Platform.environment['USERDOMAIN']?.trim();
    final user = Platform.environment['USERNAME']?.trim();
    final account = domain == null || domain.isEmpty ? user : '$domain\\$user';
    const elevatedCommand =
        r'& $env:WGMFA_PROVISION_SCRIPT '
        r'-ConfigPath $env:WGMFA_CONFIG_PATH '
        r'-TunnelUser $env:WGMFA_TUNNEL_USER';
    final encodedCommand = base64Encode([
      for (final unit in elevatedCommand.codeUnits) ...[unit & 0xff, unit >> 8],
    ]);
    final command =
        "\$process = Start-Process -FilePath 'powershell.exe' "
        "-ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand','$encodedCommand') "
        "-Verb RunAs -Wait -PassThru; exit \$process.ExitCode";
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
      runInShell: false,
      environment: {
        ...Platform.environment,
        'WGMFA_PROVISION_SCRIPT': script,
        'WGMFA_CONFIG_PATH': temporaryConfig.path,
        'WGMFA_TUNNEL_USER': account ?? '',
      },
    );
    if (result.exitCode != 0) {
      final logPath =
          '${Platform.environment['ProgramData']}'
          '${Platform.pathSeparator}WireGuard MFA Client'
          '${Platform.pathSeparator}provision.log';
      throw StateError(
        'WireGuardトンネルを設定できませんでした（終了コード: ${result.exitCode}）。ログ: $logPath',
      );
    }
  } finally {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }
}
