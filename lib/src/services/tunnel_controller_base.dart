enum TunnelState {
  stopped,
  starting,
  running,
  stopping,
  notInstalled,
  unsupported,
  unknown,
}

abstract interface class TunnelController {
  bool get isSupported;
  Future<TunnelState> getState(String tunnelName);
  Future<void> start(String tunnelName);
  Future<void> stop(String tunnelName);
}

class TunnelException implements Exception {
  const TunnelException(this.code, [this.details = '']);

  final String code;
  final String details;
}
