import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsRepository {
  static const _serverUrlKey = 'server_url';
  static const _peerUuidKey = 'peer_uuid';
  static const _tunnelNameKey = 'tunnel_name';

  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings(
      serverUrl: preferences.getString(_serverUrlKey) ?? '',
      peerUuid: preferences.getString(_peerUuidKey) ?? '',
      tunnelName: preferences.getString(_tunnelNameKey) ?? 'wg0',
    );
  }

  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(_serverUrlKey, settings.serverUrl.trim()),
      preferences.setString(_peerUuidKey, settings.peerUuid.trim()),
      preferences.setString(_tunnelNameKey, settings.tunnelName.trim()),
    ]);
  }
}
