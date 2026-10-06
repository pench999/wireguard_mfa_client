# Android development build

This branch adds Android VPN control without changing the Windows release.
It embeds the official WireGuard tunnel library (1.0.20260102).

## Scope

- Android 8.0 (API 26) or newer; initial test device: Pixel 6 Pro.
- Existing WebAdmin provisioning and MFA client-session APIs.
- External browser authentication. Return to the client after browser MFA.
- Encrypted configuration in app-private, non-backup storage; AES-GCM key in Android Keystore.
- Android VPN permission is requested on first connection, not during provisioning.
- A foreground notification maintains the app process while connected.
- No automatic connection on reboot or process restart; a new connection requires MFA.
- Screen-off does not trigger the Windows sleep/disconnect behavior.

## Build and test

Use a short checkout path outside OneDrive for Gradle builds:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

The APK is debug-signed and intended for validation, not production distribution.
Use a separate Android test user/peer because the server allows one registered
device per user. A separately installed WireGuard app is not required.

## Acceptance checks

1. Enter the server URL, log in in the external browser, complete MFA, and return to the client.
2. Check provisioning completes without opening a VPN tunnel.
3. Connect, complete MFA, return to the client, and approve the Android VPN dialog.
4. Verify internal connectivity, DNS resolution, and the foreground notification.
5. Turn the screen off, then confirm traffic still flows after unlocking.
6. Disconnect, deny VPN permission on a fresh installation, and verify failed connections are handled.
7. Verify revocation/re-registration and Wi-Fi/mobile network changes.

Native integration, DNS, service lifecycle, screen-off, and the Android 17 VPN
permission behavior require real-device acceptance testing. Dart unit tests do
not prove these behaviors. Android Always-on VPN is outside this first version.
