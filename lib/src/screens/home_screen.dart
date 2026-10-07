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
import '../services/authentication_polling.dart';
import '../services/device_identity_repository.dart';
import '../services/power_event_service.dart';
import '../services/settings_repository.dart';
import '../services/tunnel_controller.dart';
import '../services/tunnel_provisioner.dart';
import 'mfa_auth_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TrayListener, WindowListener, WidgetsBindingObserver {
  final _settingsRepository = SettingsRepository();
  final _mfaApi = MfaApi();
  final _deviceIdentityRepository = SecureDeviceIdentityRepository();
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
    WidgetsBinding.instance.addObserver(this);
    _controller = VpnController(
      api: _mfaApi,
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
    final tunnelInstalled = await _controller.initialize(settings);
    if (mounted && (!settings.isComplete || !tunnelInstalled)) {
      await _startProvisioning();
    }
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
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      unawaited(_controller.refreshConnection(_settings));
    }
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

  Future<void> _startProvisioning() async {
    if (_controller.isBusy) return;
    final serverUrl = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ServerDialog(initial: _settings.serverUrl),
    );
    if (serverUrl == null || !mounted) return;
    try {
      final serverUri = Uri.parse(
        serverUrl.endsWith('/') ? serverUrl : '$serverUrl/',
      );
      final device = await _deviceIdentityRepository.loadOrCreate();
      final session = await _mfaApi.createProvisioningSession(
        serverUri,
        device,
      );
      if (!mounted) return;
      var cancelled = false;
      var authorized = false;
      unawaited(
        showMfaAuthDialog(context, session.browserUrl).then((result) {
          if (result == MfaAuthDialogResult.cancelled) cancelled = true;
        }),
      );
      while (DateTime.now().isBefore(session.expiresAt)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (cancelled) throw StateError('初期設定がキャンセルされました。');
        if (!mounted) return;
        if (!canPollAuthentication) continue;
        final state = await _mfaApi.getProvisioningStatus(serverUri, session);
        if (state.status == 'authorized') {
          authorized = true;
          break;
        }
        if (state.status == 'failed' || state.status == 'expired') {
          throw StateError('サーバーで初期設定を完了できませんでした。');
        }
      }
      if (!authorized) throw StateError('初期設定の認証時間が切れました。もう一度認証してください。');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(MfaAuthDialogResult.completed);
      }
      _showProvisioningProgress();
      final provisioned = await _mfaApi.downloadProvisioningConfig(
        serverUri,
        session,
      );
      await provisionTunnel(provisioned.tunnelName, provisioned.config);
      final settings = AppSettings(
        serverUrl: serverUrl,
        peerUuid: provisioned.peerUuid,
        tunnelName: provisioned.tunnelName,
      );
      await _settingsRepository.save(settings);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _settings = settings);
      await _controller.initialize(settings);
    } catch (error) {
      if (!mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('初期設定に失敗しました'),
          content: Text(
            error is MfaApiException && error.code == 'network_unavailable'
                ? 'サーバーの名前解決または通信に失敗しました。ネットワークとDNS設定を確認して再試行してください。'
                : error.toString().replaceFirst('Bad state: ', ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    }
  }

  void _showProvisioningProgress() {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 18),
              Expanded(child: Text('サーバーに接続しています...')),
            ],
          ),
        ),
      ),
    );
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
            onPressed: _controller.isBusy || _loading
                ? null
                : _startProvisioning,
            tooltip: '再設定',
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
                      lockMode: _controller.lockMode,
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
    this.lockMode,
  });

  final AppSettings settings;
  final DateTime? unlockedUntil;
  final String? lockMode;

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
            if (lockMode == 'disconnect' || unlockedUntil != null) ...[
              const Divider(height: 24),
              _DetailRow(
                label: 'MFA有効期限',
                value: lockMode == 'disconnect'
                    ? '切断検知まで有効'
                    : unlockedUntil!.toLocal().toString().substring(0, 16),
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

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.initial});
  final String initial;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _server;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('MFA Clientの初期設定', style: TextStyle(fontSize: 20)),
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
                validator: (value) {
                  final uri = Uri.tryParse(value?.trim() ?? '');
                  if (uri == null ||
                      !uri.hasAuthority ||
                      (uri.scheme != 'https' && uri.scheme != 'http')) {
                    return 'HTTPまたはHTTPSのサーバーURLを入力してください。';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initial.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
        FilledButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _server.text.trim());
            }
          },
          icon: const Icon(Icons.login),
          label: const Text('認証を開始'),
        ),
      ],
    );
  }
}
