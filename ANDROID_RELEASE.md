# Android Release Preparation

Initial Android release: 1.0.0 (versionCode 22). The shared pubspec is unchanged
to avoid changing the Windows version. Android release builds override the
version explicitly. Do not publish until signed-APK acceptance passes.

## Signing key

Run from the checkout using your normal Windows account:

```powershell
.\tool\init_android_signing.ps1
.\tool\build_android_release.ps1
```

Specify `-KeyTool`, `-Flutter`, and `-AndroidSdk` if tools are elsewhere.
The private key is under `%LOCALAPPDATA%\WireGuardMfaClient\signing`, outside
OneDrive and the checkout. Passwords are random and stored using Windows DPAPI
(`Export-Clixml`), readable only by the original Windows account on the original
machine. They reach keytool and Gradle through process environment variables,
never command-line password arguments or tracked files. Scripts never overwrite
an existing key. Gradle refuses release builds without release credentials.

## Mandatory backup

Copy `android-release.jks` to a protected offline backup. DPAPI credentials alone
are NOT a portable backup. Store the actual keystore password in an organizational
password manager separately. On the original machine/account, this local command
copies it to the clipboard without printing it:

```powershell
$file = Join-Path $env:LOCALAPPDATA 'WireGuardMfaClient\signing\android-release-password.clixml'
$credential = Import-Clixml -LiteralPath $file
Set-Clipboard -Value $credential.GetNetworkCredential().Password
```

Paste into your password manager, then clear with `Set-Clipboard -Value ''`.
Do not send the private key or password in chat, commits, release assets, or logs.
Recovery requires the keystore, password, and alias `wgmfa-release`. On another
machine/account, recreate the local DPAPI credential with `Read-Host -AsSecureString`
and `Export-Clixml`; never generate a replacement signing key.

## Artifacts

The build uses a fresh short-path copy outside OneDrive, retained for diagnostics.
Output is `dist/android/1.0.0/`: signed universal APK, SHA256SUMS.txt, public signing
certificate, signature verification, APK metadata, and release notes.
The build also packages a distribution ZIP with Flutter, AndroidX, WireGuard and
Go license notices. Distribute this ZIP and its checksum alongside the APK.
Verification checks the APK signature against the keystore's public certificate,
versionCode/versionName, and absence of the debuggable flag. Future updates must
use the same key and a strictly increasing versionCode.

Release signing differs from development signing. Uninstalling the test app erases
app data/device identity and requires server-side device re-registration. Get
approval before uninstalling. Google Play and public GitHub release creation are
separate approval steps.
