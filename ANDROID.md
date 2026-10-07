# Android development build

This branch adds Android VPN control without changing the Windows release.
It embeds the official WireGuard tunnel library (1.0.20260102).

## Scope

- Android 8.0 (API 26) or newer; initial test device: Pixel 6 Pro.
- Existing WebAdmin provisioning and MFA client-session APIs.
- External browser authentication. Compatible servers automatically attempt to
  return to the client after MFA; an app-return button remains available if the
  browser requires a user gesture. Older servers require a manual return.
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

The fixed `wireguardmfa://auth/complete` link only foregrounds the existing app
task. It does not carry credentials or grant VPN access. Polling verifies the
current authenticated session before configuration retrieval or VPN startup.

## Authorization expiry

The status API's `lock_mode` selects the behavior. `disconnect` displays an
until-disconnection label, ignores the server's sentinel date, and schedules no
local expiry. `time` passes the actual deadline to the native tunnel runtime.
The foreground runtime checks a monotonic deadline and sets an idle-allowed
wakeup alarm. Expiry stops the tunnel and its foreground notification without
waiting for a server request. Returning to the app refreshes the connection state.
Old connection callbacks cannot expire a newly authenticated connection.

Android may defer the wakeup alarm in deep idle; the app does not request exact
alarm access. Server-side expiry remains the security boundary. Validate both
screen-on and screen-locked expiry, notification removal, VPN icon removal,
re-authentication, and switching to another VPN on a physical device.
