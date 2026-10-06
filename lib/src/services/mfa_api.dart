import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../models/mfa_session.dart';
import '../models/device_identity.dart';
import '../models/provisioning_session.dart';

class MfaApiException implements Exception {
  const MfaApiException(this.code, [this.statusCode]);

  final String code;
  final int? statusCode;
}

class MfaApi {
  MfaApi({http.Client? client, bool? requestAppReturn})
    : _client = client ?? http.Client(),
      _requestAppReturn =
          requestAppReturn ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final http.Client _client;
  final bool _requestAppReturn;

  Uri _browserReturnUrl(Uri uri) => _requestAppReturn
      ? uri.replace(
          queryParameters: <String, dynamic>{
            ...uri.queryParametersAll,
            'return_to_app': 'android',
          },
        )
      : uri;

  Future<http.Response> _getStatusResponse(Uri uri, String token) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _client
            .get(uri, headers: {'Authorization': 'Bearer $token'})
            .timeout(const Duration(seconds: 12));
      } on http.ClientException {
        if (attempt == 2) throw const MfaApiException('network_unavailable');
      } on TimeoutException {
        if (attempt == 2) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    throw const MfaApiException('network_unavailable');
  }

  Future<ProvisioningSession> createProvisioningSession(
    Uri serverUri,
    DeviceIdentity device,
  ) async {
    final response = await _client
        .post(
          serverUri.resolve('/api/client/v1/provisioning/'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_id': device.id,
            'device_token': device.token,
            'device_name': device.name,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final data = _decode(response);
    if (response.statusCode != 201) {
      throw MfaApiException(
        data['error']?.toString() ?? 'provisioning_failed',
        response.statusCode,
      );
    }
    final returnedUri = _browserReturnUrl(
      Uri.parse(data['browser_url'] as String),
    );
    return ProvisioningSession(
      id: data['session_id'] as String,
      browserUrl: serverUri.resolveUri(
        Uri(
          path: returnedUri.path,
          query: returnedUri.hasQuery ? returnedUri.query : null,
        ),
      ),
      pollToken: data['poll_token'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
    );
  }

  Future<ProvisioningState> getProvisioningStatus(
    Uri serverUri,
    ProvisioningSession session,
  ) async {
    final response = await _getStatusResponse(
      serverUri.resolve('/api/client/v1/provisioning/${session.id}/status/'),
      session.pollToken,
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw MfaApiException(
        data['error']?.toString() ?? 'status_failed',
        response.statusCode,
      );
    }
    return ProvisioningState(
      status: data['status']?.toString() ?? 'unknown',
      peerUuid: data['peer_uuid']?.toString(),
      tunnelName: data['tunnel_name']?.toString(),
      errorCode: data['error_code']?.toString(),
    );
  }

  Future<ProvisionedConfig> downloadProvisioningConfig(
    Uri serverUri,
    ProvisioningSession session,
  ) async {
    final response = await _client
        .get(
          serverUri.resolve(
            '/api/client/v1/provisioning/${session.id}/config/',
          ),
          headers: {'Authorization': 'Bearer ${session.pollToken}'},
        )
        .timeout(const Duration(seconds: 12));
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw MfaApiException(
        data['error']?.toString() ?? 'config_download_failed',
        response.statusCode,
      );
    }
    return ProvisionedConfig(
      peerUuid: data['peer_uuid'] as String,
      tunnelName: data['tunnel_name'] as String,
      config: data['config'] as String,
    );
  }

  Future<MfaSession> createSession(
    Uri serverUri,
    String peerUuid,
    DeviceIdentity device,
  ) async {
    final response = await _client
        .post(
          serverUri.resolve('/api/client/v1/sessions/'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'peer_uuid': peerUuid,
            'device_id': device.id,
            'device_token': device.token,
            'device_name': device.name,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final data = _decode(response);
    if (response.statusCode != 201) {
      throw MfaApiException(
        data['error']?.toString() ?? 'session_create_failed',
        response.statusCode,
      );
    }
    final browserUri = _browserReturnUrl(
      Uri.parse(data['browser_url'] as String),
    );
    final browserUrl = serverUri.resolveUri(
      Uri(
        path: browserUri.path,
        query: browserUri.hasQuery ? browserUri.query : null,
        fragment: browserUri.hasFragment ? browserUri.fragment : null,
      ),
    );
    return MfaSession(
      id: data['session_id'] as String,
      browserUrl: browserUrl,
      pollToken: data['poll_token'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
    );
  }

  Future<MfaSessionState> getStatus(Uri serverUri, MfaSession session) async {
    final response = await _getStatusResponse(
      serverUri.resolve('/api/client/v1/sessions/${session.id}/status/'),
      session.pollToken,
    );
    final data = _decode(response);
    if (response.statusCode != 200) {
      throw MfaApiException(
        data['error']?.toString() ?? 'status_failed',
        response.statusCode,
      );
    }
    return MfaSessionState(
      status: MfaSessionStatus.parse(data['status']?.toString() ?? ''),
      expiresAt: DateTime.parse(data['expires_at'] as String),
      unlockedUntil: data['unlocked_until'] == null
          ? null
          : DateTime.parse(data['unlocked_until'] as String),
      errorCode: data['error_code']?.toString(),
    );
  }

  Future<void> lock(Uri serverUri, MfaSession session) async {
    final response = await _client
        .post(
          serverUri.resolve('/api/client/v1/sessions/${session.id}/lock/'),
          headers: {'Authorization': 'Bearer ${session.pollToken}'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      final data = _decode(response);
      throw MfaApiException(
        data['error']?.toString() ?? 'lock_failed',
        response.statusCode,
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on FormatException {
      throw MfaApiException('invalid_response', response.statusCode);
    }
  }

  void close() => _client.close();
}
