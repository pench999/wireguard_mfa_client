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
    String escape(String value) => value.replaceAll("'", "''");
    final command =
        "\$process = Start-Process -FilePath 'powershell.exe' "
        "-ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','${escape(script)}','-ConfigPath','${escape(temporaryConfig.path)}','-TunnelUser','${escape(account ?? '')}') "
        "-Verb RunAs -Wait -PassThru; exit \$process.ExitCode";
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      command,
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw StateError('WireGuardトンネルを設定できませんでした（終了コード: ${result.exitCode}）。');
    }
  } finally {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }
}
