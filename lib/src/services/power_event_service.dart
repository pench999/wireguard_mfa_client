import 'package:flutter/services.dart';

enum PowerEvent { suspend, resume }

class PowerEventService {
  PowerEventService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('wireguard_mfa_client/power');

  final MethodChannel _channel;
  Future<void> Function(PowerEvent event)? _handler;

  void start(Future<void> Function(PowerEvent event) handler) {
    _handler = handler;
    _channel.setMethodCallHandler(_onMethodCall);
  }

  void stop() {
    _handler = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _onMethodCall(MethodCall call) async {
    final event = switch (call.method) {
      'suspend' => PowerEvent.suspend,
      'resume' => PowerEvent.resume,
      _ => null,
    };
    final handler = _handler;
    if (event != null && handler != null) {
      await handler(event);
    }
  }
}
