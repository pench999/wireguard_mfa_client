$ErrorActionPreference = 'Continue'

$wireGuard = @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) |
    Where-Object { $_ } |
    ForEach-Object { Join-Path $_ 'WireGuard\wireguard.exe' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1

if ($wireGuard) {
    Get-Service -Name 'WireGuardTunnel$wgmfa_*' -ErrorAction SilentlyContinue | ForEach-Object {
        $tunnelName = $_.Name.Substring('WireGuardTunnel$'.Length)
        & $wireGuard /uninstalltunnelservice $tunnelName | Out-Null
    }
}

$configDirectory = Join-Path $env:ProgramData 'WireGuard MFA Client'
Remove-Item -LiteralPath $configDirectory -Recurse -Force -ErrorAction SilentlyContinue
