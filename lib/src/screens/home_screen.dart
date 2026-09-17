import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/vpn_controller.dart';
import '../models/app_settings.dart';
import '../services/mfa_api.dart';
import '../services/device_identity_repository.dart';
import '../services/settings_repository.dart';
import '../services/tunnel_controller.dart';
import 'mfa_auth_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _settingsRepository = SettingsRepository();
  late final VpnController _controller;
  AppSettings _settings = AppSettings.empty;
  bool _loading = true;
  bool _authDialogOpen = false;
  bool _closingAuthDialog = false;

  @override
  void initState() {
    super.initState();
    _controller = VpnController(
      api: MfaApi(),
      tunnel: createTunnelController(),
      deviceIdentityRepository: SecureDeviceIdentityRepository(),
      browserLauncher: _openAuthentication,
    )..addListener(_refresh);
    _load();
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
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
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
