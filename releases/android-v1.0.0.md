# WireGuard MFA Client Android 1.0.0

Status: released on 2026-10-07. Signed-APK initial setup and VPN connectivity
were confirmed by the operator; the release signing key and password were backed up.
Version code: 22. Package: `jp.co.fairway.wireguard_mfa_client`.
Windows release version remains unchanged.

## Included

- Android 8.0/API 26 or newer; development builds validated on Pixel 6 Pro, Android 17.
- Server-based configuration provisioning without manually importing a conf file.
- External-browser login/MFA and automatic app-return on a compatible server.
- Android VPN permission and embedded official WireGuard tunnel library.
- Encrypted configuration in app-private storage, with Android Keystore protection.
- Shared authentication-gate launcher design and foreground connection notification.
- Time-lock expiry stops the local tunnel; disconnect-lock mode displays no sentinel date.
- DNS transport retry during authentication and connection-state refresh on app return.

## Known limits

- Authentication currently uses an external browser, not an embedded WebView.
- One active VPN per Android user/profile. Another VPN replaces this connection.
- Deep idle may delay local expiry processing; server-side MFA expiry enforces access.
- No automatic reconnection on boot and no Always-on VPN support.
- Initial registration requires a compatible server and an assigned peer.
- Not published to Google Play. First distribution is a signed APK for internal use.

## Moving from a development APK

The debug-signed APK cannot be updated in place with the release signing key.
Uninstalling erases client settings, encrypted configuration, and device identity.
Stop the VPN, uninstall the development APK, allow re-registration of the old
registered device on the server, install the release APK, and provision again.
MFA enrollment need not be reset solely because the APK signing key changed.

## Maintenance Checklist

- Back up the release keystore AND a recoverable copy of its password.
- Install the signed APK and provision, authenticate, connect, resolve DNS, disconnect.
- Verify screen-on and screen-locked authorization expiry, plus re-authentication.
- Verify disconnect-lock label/behavior and replacement by another VPN.
- Install the same signed APK with `adb install -r` and confirm settings remain.
- Use this same signing key and a larger versionCode for every future update.
