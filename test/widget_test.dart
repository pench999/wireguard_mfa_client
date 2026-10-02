import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wireguard_mfa_client/src/app.dart';

void main() {
  testWidgets('shows initial provisioning settings', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const WireGuardMfaApp());
    await tester.pumpAndSettle();

    expect(find.text('WireGuard MFA Client'), findsOneWidget);
    expect(find.text('MFA Clientの初期設定'), findsOneWidget);
    expect(find.text('サーバーURL'), findsOneWidget);
    expect(find.text('認証を開始'), findsOneWidget);
    expect(find.text('peer UUID'), findsNothing);
  });
}
