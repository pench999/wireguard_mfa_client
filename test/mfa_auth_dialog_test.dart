import 'package:flutter_test/flutter_test.dart';
import 'package:wireguard_mfa_client/src/screens/mfa_auth_dialog_io.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

void main() {
  test('retry pages never suppress certificate or transport errors', () {
    for (final status in WebErrorStatus.values) {
      expect(
        canDisplayRetryPage(status),
        status == WebErrorStatus.unknown ||
            status == WebErrorStatus.errorHttpInvalidServerResponse,
      );
    }
  });
  test('accepts only the configured origin', () {
    final expected = Uri.parse('https://vpn.example.com/client/connect/token/');

    expect(
      isSameOrigin(
        expected,
        Uri.parse('https://vpn.example.com/accounts/login/'),
      ),
      isTrue,
    );
    expect(
      isSameOrigin(
        expected,
        Uri.parse('http://vpn.example.com/accounts/login/'),
      ),
      isFalse,
    );
    expect(
      isSameOrigin(expected, Uri.parse('https://other.example.com/')),
      isFalse,
    );
    expect(
      isSameOrigin(expected, Uri.parse('https://vpn.example.com:444/')),
      isFalse,
    );
  });
}
