// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../models/mfa_session.dart';
import '../services/mfa_api.dart';
import '../services/authentication_polling.dart';
import '../services/device_identity_repository.dart';
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
    required DeviceIdentityRepository deviceIdentityRepository,
    BrowserLauncher? browserLauncher,
  }) : _api = api,
       _tunnel = tunnel,
       _deviceIdentityRepository = deviceIdentityRepository,
       _browserLauncher =
           browserLauncher ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final MfaApi _api;
  final TunnelController _tunnel;
  final DeviceIdentityRepository _deviceIdentityRepository;
  final BrowserLauncher _browserLauncher;

  ConnectionPhase phase = ConnectionPhase.idle;
  String message = '接続できます';
  String? errorMessage;
  DateTime? unlockedUntil;
  String? lockMode;
  Timer? _connectionMonitor;
  bool _checkingConnection = false;
  int _connectionEpoch = 0;
  MfaSession? _session;
  bool _cancelRequested = false;

  bool get isBusy => switch (phase) {
    ConnectionPhase.waitingForMfa ||
    ConnectionPhase.startingTunnel ||
    ConnectionPhase.disconnecting => true,
    _ => false,
  };

  bool get isConnected => phase == ConnectionPhase.connected;

  Future<bool> initialize(AppSettings settings) async {
    _connectionEpoch++;
    if (!_tunnel.isSupported) {
      phase = ConnectionPhase.unsupported;
      message = 'このプラットフォームではVPN制御を利用できません';
      notifyListeners();
      return true;
    }
    if (!settings.isComplete) return false;
    final state = await _tunnel.getState(settings.tunnelName);
    errorMessage = null;
    if (state == TunnelState.running) {
      final tunnel = _tunnel;
      if (tunnel is AuthorizedTunnelController) {
        unlockedUntil = await (tunnel as AuthorizedTunnelController)
            .getAuthorizationDeadline(settings.tunnelName);
        lockMode = unlockedUntil == null ? 'disconnect' : 'time';
      }
      phase = ConnectionPhase.connected;
      message = 'WireGuard接続済み';
      _connectionMonitor?.cancel();
      _connectionMonitor = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(refreshConnection(settings));
      });
    } else if (state == TunnelState.notInstalled) {
      _setError('WireGuardTunnel\$${settings.tunnelName}を事前にインストールしてください。');
      return false;
    } else {
      _connectionMonitor?.cancel();
      phase = ConnectionPhase.idle;
      message = state == TunnelState.expired
          ? '認証期限が切れました。再認証してください'
          : '接続できます';
    }
    notifyListeners();
    return true;
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
    _connectionEpoch++;
    errorMessage = null;
    unlockedUntil = null;
    lockMode = null;
    _connectionMonitor?.cancel();
    try {
      phase = ConnectionPhase.waitingForMfa;
      message = 'MFA認証を開始しています';
      notifyListeners();
      final serverUri = Uri.parse(settings.serverUrl.trim());
      final device = await _deviceIdentityRepository.loadOrCreate();
      _session = await _api.createSession(
        serverUri,
        settings.peerUuid.trim(),
        device,
      );
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
        if (!canPollAuthentication) continue;
        final state = await _api.getStatus(serverUri, _session!);
        switch (state.status) {
          case MfaSessionStatus.pending:
          case MfaSessionStatus.authorizing:
            continue;
          case MfaSessionStatus.unlocked:
            lockMode = state.lockMode;
            unlockedUntil = lockMode == 'disconnect'
                ? null
                : state.unlockedUntil;
            if (unlockedUntil != null &&
                !DateTime.now().isBefore(unlockedUntil!)) {
              throw const MfaApiException('session_expired');
            }
            phase = ConnectionPhase.startingTunnel;
            message = 'WireGuardを起動しています';
            notifyListeners();
            try {
              final tunnel = _tunnel;
              if (tunnel is AuthorizedTunnelController) {
                await (tunnel as AuthorizedTunnelController).startAuthorized(
                  settings.tunnelName.trim(),
                  unlockedUntil,
                );
              } else {
                await tunnel.start(settings.tunnelName.trim());
              }
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
            _connectionMonitor = Timer.periodic(const Duration(seconds: 2), (
              _,
            ) {
              unawaited(refreshConnection(settings));
            });
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
    await _disconnect(settings, messageAfterStop: '切断しました');
  }

  Future<void> refreshConnection(AppSettings settings) async {
    if (!isConnected || _checkingConnection) return;
    _checkingConnection = true;
    final epoch = _connectionEpoch;
    try {
      final expired =
          unlockedUntil != null && !DateTime.now().isBefore(unlockedUntil!);
      final state = await _tunnel.getState(settings.tunnelName.trim());
      if (!isConnected || epoch != _connectionEpoch) return;
      if (expired) {
        // Stop locally without waiting for an unreachable server's lock API.
        await _tunnel.stop(settings.tunnelName.trim());
        if (epoch != _connectionEpoch) return;
      }
      if (expired ||
          state == TunnelState.expired ||
          state == TunnelState.stopped) {
        _connectionMonitor?.cancel();
        phase = ConnectionPhase.idle;
        message = expired || state == TunnelState.expired
            ? '認証期限が切れました。再認証してください'
            : 'VPNは切断されています。再接続にはMFA認証が必要です';
        unlockedUntil = null;
        lockMode = null;
        _session = null;
        notifyListeners();
      }
    } on TunnelException catch (error) {
      if (epoch == _connectionEpoch) {
        _connectionMonitor?.cancel();
        _setError(_messageForTunnelError(error));
      }
    } finally {
      _checkingConnection = false;
    }
  }

  Future<void> handleSuspend(AppSettings settings) async {
    await _disconnect(settings, messageAfterStop: 'スリープのため切断しました');
  }

  Future<void> handleResume(AppSettings settings) async {
    _connectionEpoch++;
    _connectionMonitor?.cancel();
    _cancelRequested = true;
    phase = ConnectionPhase.disconnecting;
    message = '復帰後の接続状態を確認しています';
    errorMessage = null;
    notifyListeners();
    try {
      if (_tunnel.isSupported && settings.tunnelName.isNotEmpty) {
        final tunnelName = settings.tunnelName.trim();
        final state = await _tunnel.getState(tunnelName);
        if (state == TunnelState.running || state == TunnelState.starting) {
          await _tunnel.stop(tunnelName);
        }
      }
      _session = null;
      unlockedUntil = null;
      phase = ConnectionPhase.idle;
      message = '復帰しました。再接続にはMFA認証が必要です';
      lockMode = null;
      notifyListeners();
    } on TunnelException catch (error) {
      _setError(_messageForTunnelError(error));
    }
  }

  Future<void> _disconnect(
    AppSettings settings, {
    required String messageAfterStop,
  }) async {
    _cancelRequested = true;
    _connectionEpoch++;
    _connectionMonitor?.cancel();
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
      message = lockWarning ?? messageAfterStop;
      lockMode = null;
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
    'network_unavailable' => 'サーバーへ接続できません。ネットワークとDNS設定を確認して再試行してください。',
    'invalid_device' => '端末情報を作成できませんでした。アプリを再起動してください。',
    'device_required' => 'このユーザーは登録済み端末からのみ接続できます。',
    'device_unauthorized' => 'この端末の登録情報を確認できません。管理者に再登録を依頼してください。',
    'device_revoked' => 'この端末は管理者によって失効されています。',
    'device_registration_not_allowed' => '別の端末が登録されています。管理者に再登録の許可を依頼してください。',
    _ => 'MFAサーバーとの処理に失敗しました。',
  };

  String _messageForTunnelError(TunnelException error) => switch (error.code) {
    'vpn_permission_denied' => 'AndroidのVPN利用許可がキャンセルされました。再接続して許可してください。',
    'service_start_failed' => 'WireGuardサービスを開始できません。権限とサービス設定を確認してください。',
    'service_stop_failed' => 'WireGuardサービスを停止できません。',
    'service_start_timeout' => 'WireGuardサービスの起動確認がタイムアウトしました。',
    'unsupported_platform' => 'このプラットフォームではVPN制御を利用できません。',
    _ => 'WireGuardサービスの操作に失敗しました。',
  };

  @override
  void dispose() {
    _connectionEpoch++;
    _connectionMonitor?.cancel();
    _cancelRequested = true;
    _api.close();
    super.dispose();
  }
}
