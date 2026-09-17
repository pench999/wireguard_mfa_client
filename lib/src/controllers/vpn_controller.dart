import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../models/mfa_session.dart';
import '../services/mfa_api.dart';
import '../services/tunnel_controller.dart';

enum ConnectionPhase {
  idle,
  waitingForMfa,
  startingTunnel,
  connected,
  disconnecting,
  error,
  unsupported,
}

typedef BrowserLauncher = Future<bool> Function(Uri uri);

class VpnController extends ChangeNotifier {
  VpnController({
    required MfaApi api,
    required TunnelController tunnel,
    BrowserLauncher? browserLauncher,
  }) : _api = api, // ignore: prefer_initializing_formals
       _tunnel = tunnel, // ignore: prefer_initializing_formals
       _browserLauncher =
           browserLauncher ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final MfaApi _api;
  final TunnelController _tunnel;
  final BrowserLauncher _browserLauncher;

  ConnectionPhase phase = ConnectionPhase.idle;
  String message = '接続できます';
  String? errorMessage;
  DateTime? unlockedUntil;
  MfaSession? _session;
  bool _cancelRequested = false;

  bool get isBusy => switch (phase) {
    ConnectionPhase.waitingForMfa ||
    ConnectionPhase.startingTunnel ||
    ConnectionPhase.disconnecting => true,
    _ => false,
  };

  bool get isConnected => phase == ConnectionPhase.connected;

  Future<void> initialize(AppSettings settings) async {
    if (!_tunnel.isSupported) {
      phase = ConnectionPhase.unsupported;
      message = 'このプラットフォームではVPN制御を利用できません';
      notifyListeners();
      return;
    }
    if (!settings.isComplete) return;
    final state = await _tunnel.getState(settings.tunnelName);
    if (state == TunnelState.running) {
      phase = ConnectionPhase.connected;
      message = 'WireGuard接続済み';
    } else if (state == TunnelState.notInstalled) {
      _setError('WireGuardTunnel\$${settings.tunnelName}を事前にインストールしてください。');
      return;
    }
    notifyListeners();
  }

  Future<void> connect(AppSettings settings) async {
    final validationError = settings.validate();
    if (validationError != null) {
      _setError(validationError);
      return;
    }
    if (!_tunnel.isSupported) {
      phase = ConnectionPhase.unsupported;
      notifyListeners();
      return;
    }

    _cancelRequested = false;
    errorMessage = null;
    unlockedUntil = null;
    try {
      phase = ConnectionPhase.waitingForMfa;
      message = 'MFA認証を開始しています';
      notifyListeners();
      final serverUri = Uri.parse(settings.serverUrl.trim());
      _session = await _api.createSession(serverUri, settings.peerUuid.trim());
      if (!await _browserLauncher(_session!.browserUrl)) {
        throw const MfaApiException('browser_launch_failed');
      }
      message = 'ブラウザでMFA認証を完了してください';
      notifyListeners();

      while (!_cancelRequested &&
          DateTime.now().isBefore(_session!.expiresAt)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (_cancelRequested) {
          return;
        }
        final state = await _api.getStatus(serverUri, _session!);
        switch (state.status) {
          case MfaSessionStatus.pending:
          case MfaSessionStatus.authorizing:
            continue;
          case MfaSessionStatus.unlocked:
            unlockedUntil = state.unlockedUntil;
            phase = ConnectionPhase.startingTunnel;
            message = 'WireGuardを起動しています';
            notifyListeners();
            try {
              await _tunnel.start(settings.tunnelName.trim());
            } on TunnelException {
              try {
                await _api.lock(serverUri, _session!);
              } catch (_) {
                // The server-side timeout remains the final safety net.
              }
              rethrow;
            }
            phase = ConnectionPhase.connected;
            message = 'WireGuard接続済み';
            notifyListeners();
            return;
          case MfaSessionStatus.failed:
            throw MfaApiException(state.errorCode ?? 'peer_unlock_failed');
          case MfaSessionStatus.expired:
            throw const MfaApiException('session_expired');
          case MfaSessionStatus.cancelled:
            throw const MfaApiException('session_cancelled');
          case MfaSessionStatus.locked:
            throw const MfaApiException('peer_locked');
          case MfaSessionStatus.unknown:
            throw const MfaApiException('unknown_status');
        }
      }
      if (!_cancelRequested) throw const MfaApiException('session_expired');
    } on TimeoutException {
      _setError('サーバーとの通信がタイムアウトしました。');
    } on MfaApiException catch (error) {
      _setError(_messageForApiError(error.code));
    } on TunnelException catch (error) {
      _setError(_messageForTunnelError(error));
    } catch (_) {
      _setError('接続処理に失敗しました。');
    }
  }

  Future<void> disconnect(AppSettings settings) async {
    _cancelRequested = true;
    phase = ConnectionPhase.disconnecting;
    message = '切断しています';
    errorMessage = null;
    notifyListeners();
    String? lockWarning;
    try {
      if (_tunnel.isSupported && settings.tunnelName.isNotEmpty) {
        await _tunnel.stop(settings.tunnelName.trim());
      }
      final session = _session;
      if (session != null && settings.serverUrl.isNotEmpty) {
        try {
          await _api.lock(Uri.parse(settings.serverUrl.trim()), session);
        } catch (_) {
          lockWarning = 'VPNは停止しましたが、サーバーの即時ロックを確認できませんでした。';
        }
      }
      _session = null;
      unlockedUntil = null;
      phase = ConnectionPhase.idle;
      message = lockWarning ?? '切断しました';
      errorMessage = lockWarning;
      notifyListeners();
    } on TunnelException catch (error) {
      _setError(_messageForTunnelError(error));
    }
  }

  void cancelAuthentication() {
    _cancelRequested = true;
    phase = ConnectionPhase.idle;
    message = '認証をキャンセルしました';
    notifyListeners();
  }

  void _setError(String value) {
    phase = ConnectionPhase.error;
    message = '処理を完了できませんでした';
    errorMessage = value;
    notifyListeners();
  }

  String _messageForApiError(String code) => switch (code) {
    'peer_unavailable' => '対象peerを利用できません。サーバー設定を確認してください。',
    'too_many_sessions' => '認証要求が多すぎます。しばらく待って再試行してください。',
    'session_expired' => 'MFA認証の有効時間が切れました。',
    'browser_launch_failed' => '既定ブラウザを開けませんでした。',
    'wireguard_reload_failed' ||
    'peer_unlock_failed' => 'MFAは成功しましたが、サーバーでWireGuardを有効化できませんでした。',
    'unauthorized' => '認証セッションを確認できませんでした。',
    _ => 'MFAサーバーとの処理に失敗しました。',
  };

  String _messageForTunnelError(TunnelException error) => switch (error.code) {
    'service_start_failed' => 'WireGuardサービスを開始できません。権限とサービス設定を確認してください。',
    'service_stop_failed' => 'WireGuardサービスを停止できません。',
    'service_start_timeout' => 'WireGuardサービスの起動確認がタイムアウトしました。',
    'unsupported_platform' => 'このプラットフォームではVPN制御を利用できません。',
    _ => 'WireGuardサービスの操作に失敗しました。',
  };

  @override
  void dispose() {
    _cancelRequested = true;
    _api.close();
    super.dispose();
  }
}
