import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wireguard_mfa_client/src/app.dart';

void main() {
  testWidgets('shows initial connection settings', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const WireGuardMfaApp());
    await tester.pumpAndSettle();

    expect(find.text('WireGuard MFA Client'), findsOneWidget);
    expect(find.text('接続設定'), findsOneWidget);
    expect(find.text('サーバーURL'), findsOneWidget);
    expect(find.text('peer UUID'), findsOneWidget);
  });
}
