class ProvisioningSession {
  const ProvisioningSession({
    required this.id,
    required this.browserUrl,
    required this.pollToken,
    required this.expiresAt,
  });

  final String id;
  final Uri browserUrl;
  final String pollToken;
  final DateTime expiresAt;
}

class ProvisioningState {
  const ProvisioningState({
    required this.status,
    this.peerUuid,
    this.tunnelName,
    this.errorCode,
  });

  final String status;
  final String? peerUuid;
  final String? tunnelName;
  final String? errorCode;
}

class ProvisionedConfig {
  const ProvisionedConfig({
    required this.peerUuid,
    required this.tunnelName,
    required this.config,
  });

  final String peerUuid;
  final String tunnelName;
  final String config;
}
