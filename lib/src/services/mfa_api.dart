import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/mfa_session.dart';

class MfaApiException implements Exception {
  const MfaApiException(this.code, [this.statusCode]);

  final String code;
  final int? statusCode;
}

class MfaApi {
  MfaApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<MfaSession> createSession(Uri serverUri, String peerUuid) async {
    final response = await _client
        .post(
          serverUri.resolve('/api/client/v1/sessions/'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'peer_uuid': peerUuid}),
        )
        .timeout(const Duration(seconds: 12));
    final data = _decode(response);
    if (response.statusCode != 201) {
      throw MfaApiException(
        data['error']?.toString() ?? 'session_create_failed',
        response.statusCode,
      );
    }
    final browserUri = Uri.parse(data['browser_url'] as String);
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
    final response = await _client
        .get(
          serverUri.resolve('/api/client/v1/sessions/${session.id}/status/'),
          headers: {'Authorization': 'Bearer ${session.pollToken}'},
        )
        .timeout(const Duration(seconds: 12));
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
