// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
// tray_manager 0.7 keeps the single-icon API in its compatibility library.
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import '../controllers/vpn_controller.dart';
import '../models/app_settings.dart';
import '../services/mfa_api.dart';
import '../services/device_identity_repository.dart';
import '../services/power_event_service.dart';
import '../services/settings_repository.dart';
import '../services/tunnel_controller.dart';
import 'mfa_auth_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TrayListener, WindowListener {
  final _settingsRepository = SettingsRepository();
  final _powerEvents = PowerEventService();
  late final VpnController _controller;
  AppSettings _settings = AppSettings.empty;
  bool _loading = true;
  bool _authDialogOpen = false;
  bool _closingAuthDialog = false;
  bool _desktopReady = false;
  bool _exiting = false;
  String? _currentTrayIcon;
  Future<void> _powerOperation = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _controller = VpnController(
      api: MfaApi(),
      tunnel: createTunnelController(),
      deviceIdentityRepository: SecureDeviceIdentityRepository(),
      browserLauncher: _openAuthentication,
    )..addListener(_refresh);
    if (Platform.isWindows) {
      unawaited(_initializeDesktopIntegration());
    }
    _load();
  }

  Future<void> _initializeDesktopIntegration() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    _powerEvents.start(_handlePowerEvent);
    try {
      final executableDirectory = File(Platform.resolvedExecutable).parent.path;
      final applicationIcon =
          '$executableDirectory${Platform.pathSeparator}data'
          '${Platform.pathSeparator}tray_icon.ico';
      await windowManager.setIcon(applicationIcon);
      await trayManager.setIcon(_trayIconPath(executableDirectory, 'idle'));
      _currentTrayIcon = 'idle';
      await trayManager.setToolTip('WireGuard MFA Client');
      _desktopReady = true;
      await _updateTrayMenu();
    } catch (error) {
      debugPrint('Task tray initialization failed: $error');
    }
  }

  Future<void> _load() async {
    final settings = await _settingsRepository.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
    await _controller.initialize(settings);
    if (mounted && !settings.isComplete) await _openSettings();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    if (_desktopReady) unawaited(_updateTrayMenu());
    if (_authDialogOpen &&
        !_closingAuthDialog &&
        _controller.phase != ConnectionPhase.waitingForMfa) {
      _closingAuthDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _authDialogOpen) {
          Navigator.of(context).pop(MfaAuthDialogResult.completed);
        }
      });
    }
  }

  Future<bool> _openAuthentication(Uri authenticationUrl) async {
    if (!mounted || _authDialogOpen) return mounted;
    _authDialogOpen = true;
    _closingAuthDialog = false;
    unawaited(
      showMfaAuthDialog(context, authenticationUrl).then((result) {
        _authDialogOpen = false;
        _closingAuthDialog = false;
        if (result == MfaAuthDialogResult.cancelled) {
          _controller.cancelAuthentication();
        }
      }),
    );
    return true;
  }

  @override
  void dispose() {
    _powerEvents.stop();
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      if (!_exiting) {
        unawaited(trayManager.destroy());
      }
    }
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  Future<void> _updateTrayMenu() async {
    if (!_desktopReady) return;
    final iconState = switch (_controller.phase) {
      ConnectionPhase.connected => 'connected',
      ConnectionPhase.waitingForMfa ||
      ConnectionPhase.startingTunnel => 'authenticating',
      ConnectionPhase.error => 'error',
      _ => 'idle',
    };
    if (_currentTrayIcon != iconState) {
      final executableDirectory = File(Platform.resolvedExecutable).parent.path;
      await trayManager.setIcon(_trayIconPath(executableDirectory, iconState));
      _currentTrayIcon = iconState;
    }
    final status = _controller.isConnected
        ? '状態: 接続済み'
        : _controller.isBusy
        ? '状態: ${_controller.message}'
        : '状態: 未接続';
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: '開く'),
        MenuItem.separator(),
        MenuItem(key: 'status', label: status, disabled: true),
        MenuItem(
          key: 'toggle',
          label: _controller.isConnected ? '切断' : 'MFA認証して接続',
          disabled: _controller.isBusy || !_settings.isComplete,
        ),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '終了'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  String _trayIconPath(String executableDirectory, String state) =>
      '$executableDirectory${Platform.pathSeparator}data'
      '${Platform.pathSeparator}tray${Platform.pathSeparator}tray_$state.ico';

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> _exitApplication() async {
    if (_exiting) return;
    _exiting = true;
    await _controller.disconnect(_settings);
    _powerEvents.stop();
    if (_desktopReady) await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _handlePowerEvent(PowerEvent event) {
    _powerOperation = _powerOperation.then((_) async {
      if (_exiting) return;
      switch (event) {
        case PowerEvent.suspend:
          await _controller.handleSuspend(_settings);
        case PowerEvent.resume:
          await _controller.handleResume(_settings);
      }
    });
    return _powerOperation;
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    if (_desktopReady && (_controller.isConnected || _controller.isBusy)) {
      unawaited(windowManager.hide());
    } else {
      unawaited(_exitApplication());
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showWindow());
      case 'toggle':
        if (_controller.isConnected) {
          unawaited(_controller.disconnect(_settings));
        } else if (!_controller.isBusy) {
          unawaited(_showWindow().then((_) => _controller.connect(_settings)));
        }
      case 'exit':
        unawaited(_exitApplication());
    }
  }

  Future<void> _openSettings() async {
    final result = await showDialog<AppSettings>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SettingsDialog(initial: _settings),
    );
    if (result == null) return;
    await _settingsRepository.save(result);
    if (!mounted) return;
    setState(() => _settings = result);
    await _controller.initialize(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'WireGuard MFA Client',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: _controller.isBusy || _loading ? null : _openSettings,
            tooltip: '設定',
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _StatusPanel(controller: _controller),
                    const SizedBox(height: 18),
                    _ConnectionDetails(
                      settings: _settings,
                      unlockedUntil: _controller.unlockedUntil,
                    ),
                    if (_settings.serverUrl.startsWith('http://')) ...[
                      const SizedBox(height: 12),
                      const _Notice(
                        icon: Icons.warning_amber_rounded,
                        text: 'HTTP接続では認証情報を保護できません。本番環境ではHTTPSを使用してください。',
                      ),
                    ],
                    if (_controller.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _Notice(
                        icon: Icons.error_outline,
                        text: _controller.errorMessage!,
                        isError: true,
                      ),
                    ],
                    const SizedBox(height: 24),
                    _ActionArea(controller: _controller, settings: _settings),
                  ],
                ),
              ),
            ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final connected = controller.isConnected;
    final color = connected ? const Color(0xFF167A5A) : const Color(0xFF54615D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD8DEDC)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.shield : Icons.shield_outlined,
            color: color,
            size: 34,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? '接続済み' : '未接続',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.message,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          if (controller.isBusy)
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
        ],
      ),
    );
  }
}

class _ConnectionDetails extends StatelessWidget {
  const _ConnectionDetails({
    required this.settings,
    required this.unlockedUntil,
  });

  final AppSettings settings;
  final DateTime? unlockedUntil;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _DetailRow(
              label: 'サーバー',
              value: settings.serverUrl.isEmpty ? '未設定' : settings.serverUrl,
            ),
            const Divider(height: 24),
            _DetailRow(
              label: 'トンネル',
              value: settings.tunnelName.isEmpty ? '未設定' : settings.tunnelName,
            ),
            if (unlockedUntil != null) ...[
              const Divider(height: 24),
              _DetailRow(
                label: 'MFA有効期限',
                value: unlockedUntil!.toLocal().toString().substring(0, 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
        ),
        Expanded(child: SelectableText(value, textAlign: TextAlign.right)),
      ],
    );
  }
}

class _ActionArea extends StatelessWidget {
  const _ActionArea({required this.controller, required this.settings});
  final VpnController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    if (controller.phase == ConnectionPhase.unsupported) {
      return const Center(child: Text('VPN接続の操作はWindows版で利用できます。'));
    }
    if (controller.phase == ConnectionPhase.waitingForMfa) {
      return Center(
        child: OutlinedButton.icon(
          onPressed: controller.cancelAuthentication,
          icon: const Icon(Icons.close),
          label: const Text('認証をキャンセル'),
        ),
      );
    }
    return Center(
      child: FilledButton.icon(
        onPressed: controller.isBusy
            ? null
            : controller.isConnected
            ? () => controller.disconnect(settings)
            : () => controller.connect(settings),
        icon: Icon(controller.isConnected ? Icons.link_off : Icons.login),
        label: Text(controller.isConnected ? '切断' : 'MFA認証して接続'),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.isError = false});
  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFF9B2C2C) : const Color(0xFF8A5A00);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.initial});
  final AppSettings initial;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _server;
  late final TextEditingController _peer;
  late final TextEditingController _tunnel;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: widget.initial.serverUrl);
    _peer = TextEditingController(text: widget.initial.peerUuid);
    _tunnel = TextEditingController(text: widget.initial.tunnelName);
  }

  @override
  void dispose() {
    _server.dispose();
    _peer.dispose();
    _tunnel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('接続設定', style: TextStyle(fontSize: 20)),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _server,
                decoration: const InputDecoration(
                  labelText: 'サーバーURL',
                  hintText: 'https://vpn.example.com',
                ),
                validator: (_) =>
                    _candidate.validate()?.contains('サーバー') == true
                    ? _candidate.validate()
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _peer,
                decoration: const InputDecoration(labelText: 'peer UUID'),
                validator: (_) =>
                    _candidate.validate()?.contains('peer UUID') == true
                    ? _candidate.validate()
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _tunnel,
                decoration: const InputDecoration(
                  labelText: 'WireGuardトンネル名',
                  hintText: 'wg0',
                ),
                validator: (_) =>
                    _candidate.validate()?.contains('トンネル名') == true
                    ? _candidate.validate()
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initial.isComplete)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
        FilledButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _candidate);
            }
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存'),
        ),
      ],
    );
  }

  AppSettings get _candidate => AppSettings(
    serverUrl: _server.text,
    peerUuid: _peer.text,
    tunnelName: _tunnel.text,
  );
}
