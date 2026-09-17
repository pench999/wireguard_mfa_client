enum MfaSessionStatus {
  pending,
  authorizing,
  unlocked,
  failed,
  expired,
  cancelled,
  locked,
  unknown;

  static MfaSessionStatus parse(String value) {
    return values.firstWhere(
      (status) => status.name == value,
      orElse: () => unknown,
    );
  }
}

class MfaSession {
  const MfaSession({
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

class MfaSessionState {
  const MfaSessionState({
    required this.status,
    required this.expiresAt,
    this.unlockedUntil,
    this.errorCode,
  });

  final MfaSessionStatus status;
  final DateTime expiresAt;
  final DateTime? unlockedUntil;
  final String? errorCode;
}
