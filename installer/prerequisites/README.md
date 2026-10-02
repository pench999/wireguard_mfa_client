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

Also place the official Microsoft Edge WebView2 Evergreen Bootstrapper below:

- File: `MicrosoftEdgeWebview2Setup.exe`
- Source: `https://go.microsoft.com/fwlink/p/?LinkId=2124703`
- Version: `1.3.273.21`
- SHA-256: `48A7B31419A8EB4FFFDC7B6A02F6B4DFDA60687FC897116BE15370E10C2B66A7`
- Authenticode signer: `Microsoft Corporation`

The Bootstrapper is intentionally excluded from Git. The generated setup embeds
it and installs the current Evergreen Runtime per-machine. This step requires
access to Microsoft's download service; browser fallback remains available when
deployment is blocked by network or organization policy.

WireGuard source and license information:
`https://git.zx2c4.com/wireguard-windows/`
