import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/device_identity.dart';

abstract interface class DeviceIdentityRepository {
  Future<DeviceIdentity> loadOrCreate();
}

class SecureDeviceIdentityRepository implements DeviceIdentityRepository {
  SecureDeviceIdentityRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _idKey = 'mfa_device_id';
  static const _tokenKey = 'mfa_device_token';

  final FlutterSecureStorage _storage;

  @override
  Future<DeviceIdentity> loadOrCreate() async {
    var id = await _storage.read(key: _idKey);
    var token = await _storage.read(key: _tokenKey);
    if (id == null || token == null) {
      id = _newUuid();
      token = _newToken();
      await _storage.write(key: _idKey, value: id);
      await _storage.write(key: _tokenKey, value: token);
    }
    return DeviceIdentity(id: id, token: token, name: _deviceName());
  }

  String _deviceName() {
    final hostname = Platform.localHostname.trim();
    return hostname.isEmpty ? 'Windows device' : hostname;
  }

  String _newToken() => base64UrlEncode(_randomBytes(32)).replaceAll('=', '');

  String _newUuid() {
    final bytes = _randomBytes(16);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
