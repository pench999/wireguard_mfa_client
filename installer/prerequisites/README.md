# Bundled WireGuard prerequisite

Place the unmodified official MSI below in this directory before building:

- File: `wireguard-amd64-1.1.1.msi`
- Source: `https://download.wireguard.com/windows-client/wireguard-amd64-1.1.1.msi`
- SHA-256: `7BFED60AD61B785C914B38B61555A975488E1D3EC472DBFB2FCDF498FCA75242`
- Authenticode signer: `WireGuard LLC`

The MSI is intentionally excluded from Git. The generated MFA Client setup embeds
the verified MSI and installs it only when WireGuard for Windows is absent.

Also place the official Microsoft Visual C++ Redistributable below:

- File: `vc_redist.x64.exe`
- Source: `https://aka.ms/vs/17/release/vc_redist.x64.exe`
- Version: `14.44.35211.0`
- SHA-256: `CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B`
- Authenticode signer: `Microsoft Corporation`

The EXE is intentionally excluded from Git. It is verified during the installer
build and bundled so clean Windows PCs can run the Flutter application offline.

Also place the official Microsoft Edge WebView2 Evergreen Standalone x64
Installer below:

- File: `MicrosoftEdgeWebView2RuntimeInstallerX64.exe`
- Source: `https://go.microsoft.com/fwlink/?linkid=2124701`
- Version: `1.3.271.7`
- SHA-256: `F6DF8E4BC857786FF641CD01DA1449169EAF8236C936CED485EA61685BA4DA40`
- Authenticode signer: `Microsoft Corporation`

The Standalone Installer is intentionally excluded from Git. The generated setup
embeds it and installs the Evergreen Runtime per-machine without downloading it
during setup. Browser fallback remains available if organization policy blocks
the Runtime installation.

WireGuard source and license information:
`https://git.zx2c4.com/wireguard-windows/`
