# Bundled WireGuard prerequisite

Place the unmodified official MSI below in this directory before building:

- File: `wireguard-amd64-1.1.1.msi`
- Source: `https://download.wireguard.com/windows-client/wireguard-amd64-1.1.1.msi`
- SHA-256: `7BFED60AD61B785C914B38B61555A975488E1D3EC472DBFB2FCDF498FCA75242`
- Authenticode signer: `WireGuard LLC`

The MSI is intentionally excluded from Git. The generated MFA Client setup embeds
the verified MSI and installs it only when WireGuard for Windows is absent.

WireGuard source and license information:
`https://git.zx2c4.com/wireguard-windows/`

