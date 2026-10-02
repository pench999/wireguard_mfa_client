# Changelog

## 1.3.10 - 2026-10-02

Windows x64 release candidate. User acceptance testing was completed with no
major issues reported apart from the limitations listed below.

### Features and fixes

- Provision assigned WireGuard configurations after portal login and MFA.
- Register protected tunnel services and grant the Windows user start/stop access.
- Wait for a newly registered tunnel to stop before completing provisioning.
- Support tray operation and require MFA again after sleep/resume.
- Use WebView2 for authentication, with external browser fallback.
- Use a per-user WebView2 profile and record initialization failures.
- Bundle official ISRG Root X1/X2 certificates without disabling TLS validation.
- Bundle WireGuard for Windows 1.1.1 and the Visual C++ x64 Runtime.
- Remove WebView2 Runtime installers to reduce setup size to approximately 41 MB.
- Remove launch-on-finish from setup so users start the app in their own account.

### Requirements and limitations

- Windows 11 x64 and a WebAdmin server with provisioning/client-session APIs.
- Administrator credentials are required for setup and first tunnel registration.
- WebView2 Runtime is optional; external browser authentication is supported.
- Setup and application are not code-signed.
- Concurrent application instances are not prevented. Fully exit previous
  instances before upgrading or changing Windows user context.
- No unified log exists for normal MFA, connect, and disconnect operations.
- The cause of the previously observed per-user WebView2 fallback is not proven;
  restarting the PC or closing all instances resolved it in the reported tests.

### Validation

- Flutter static analysis passed.
- All 13 Flutter tests passed.
- Windows release build and NSIS setup compilation passed.
- User-reported acceptance testing completed; this is not an automated end-to-end test.

### Distribution

- Asset: `WireGuardMfaClient-1.3.10-windows-x64-setup.exe`
- Size: 41,311,808 bytes.
- SHA-256: `CBCA7182802ABD921B5645F99E00E750B4225C7471E507B78FE2D55EB2E3566D`

Exit the client from its tray menu before upgrading. After setup, start the
application from the intended user's Start menu. Setup does not uninstall a
previously installed shared WebView2 Runtime.
