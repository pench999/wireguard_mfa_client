class AppSettings {
  const AppSettings({
    required this.serverUrl,
    required this.peerUuid,
    required this.tunnelName,
  });

  static const empty = AppSettings(
    serverUrl: '',
    peerUuid: '',
    tunnelName: 'wg0',
  );

  final String serverUrl;
  final String peerUuid;
  final String tunnelName;

  bool get isComplete =>
      serverUrl.trim().isNotEmpty &&
      peerUuid.trim().isNotEmpty &&
      tunnelName.trim().isNotEmpty;

  String? validate() {
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'サーバーURLを正しく入力してください。';
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return 'サーバーURLはHTTPまたはHTTPSで入力してください。';
    }
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(peerUuid.trim())) {
      return 'peer UUIDを正しく入力してください。';
    }
    if (!RegExp(r'^[A-Za-z0-9_.=+-]{1,64}$').hasMatch(tunnelName.trim())) {
      return 'トンネル名に使用できない文字が含まれています。';
    }
    return null;
  }
}
