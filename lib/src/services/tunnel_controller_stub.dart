import 'tunnel_controller_base.dart';

export 'tunnel_controller_base.dart';

TunnelController createTunnelController() =>
    const UnsupportedTunnelController();

class UnsupportedTunnelController implements TunnelController {
  const UnsupportedTunnelController();

  @override
  bool get isSupported => false;
  @override
  Future<TunnelState> getState(String tunnelName) async =>
      TunnelState.unsupported;
  @override
  Future<void> start(String tunnelName) =>
      throw const TunnelException('unsupported_platform');
  @override
  Future<void> stop(String tunnelName) =>
      throw const TunnelException('unsupported_platform');
}
