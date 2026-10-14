# Windows 1.3.11

Windows x64 maintenance release (application version 1.3.11+23).

## Fixes

- Avoid overlapping the WebAdmin retry page with a WebView error overlay.
- Display identified MFA retry pages without replacing them with a network error.
- Create a fresh authentication session when switching to an external browser,
  including initial provisioning. Poll the replacement session and ignore stale
  responses from the previous session.

## Server Update

Update WebAdmin to the main branch containing the security-rate-limits changes.
Apply the user_manager 0013 migration and preserve the database and app_secrets
volume. The dedicated rate-limit HMAC key survives container restarts.
The first upgrade changes counter identities once, resetting existing limits.
Configure trusted Nginx source addresses according to SECURITY_RATE_LIMITS.md.
These controls cover OTP verification and anonymous session creation, not all APIs.
Revalidation of existing authentication sessions after device revocation remains
a separate outstanding security issue.

## Upgrade

Exit the client using its tray menu before running setup. Start the application
as the intended Windows user after setup. Administrator credentials are required
for setup and initial tunnel registration. Setup and application are not code-signed.
WireGuard and Visual C++ Runtime are bundled; WebView2 Runtime is not bundled.

## Validation

- Flutter static analysis and all 28 Flutter tests passed.
- Windows release build and NSIS setup compilation passed.
- Related WebAdmin tests: 61 passed; entrypoint shell syntax checked.
- User confirmed the reported fixes in the test environment. This does not
  represent an automated end-to-end security audit.

## Distribution

- WireGuardMfaClient-1.3.11-windows-x64-setup.exe
- Size: 41,318,839 bytes.
- SHA-256: F09B3A8B62D231BFBF009707CAB94BDAA63FB2660A87DEB70C720707C8F777E6
