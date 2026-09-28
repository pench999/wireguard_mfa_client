[CmdletBinding()]
param(
    [string]$MsiPath = $env:WGMFA_WIREGUARD_MSI
)

$ErrorActionPreference = 'Stop'
$expectedHash = '7BFED60AD61B785C914B38B61555A975488E1D3EC472DBFB2FCDF498FCA75242'

function Get-WireGuardExecutable {
    $programDirectories = @(
        $env:ProgramW6432,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($directory in $programDirectories) {
        $candidate = Join-Path $directory 'WireGuard\wireguard.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

$existingExecutable = Get-WireGuardExecutable
if ($existingExecutable) {
    Write-Output "WIREGUARD_ALREADY_INSTALLED=$existingExecutable"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($MsiPath) -or
    -not (Test-Path -LiteralPath $MsiPath -PathType Leaf)) {
    throw 'The bundled WireGuard MSI was not found.'
}

$actualHash = (Get-FileHash -LiteralPath $MsiPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "The bundled WireGuard MSI hash is invalid: $actualHash"
}

$signature = Get-AuthenticodeSignature -LiteralPath $MsiPath
if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
    -not $signature.SignerCertificate.Subject.Contains('O=WireGuard LLC')) {
    throw "The bundled WireGuard MSI signature is invalid: $($signature.Status)"
}

Write-Output 'INSTALLING_WIREGUARD_VERSION=1.1.1'
$msiexec = Join-Path $env:SystemRoot 'Sysnative\msiexec.exe'
if (-not (Test-Path -LiteralPath $msiexec -PathType Leaf)) {
    $msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
}
$msiLogPath = Join-Path $env:TEMP 'WireGuardMfaClient-wireguard-msi.log'
$msiArguments = @(
    '/i',
    ('"{0}"' -f $MsiPath),
    '/qn',
    '/norestart',
    'DO_NOT_LAUNCH=1',
    '/L*v',
    ('"{0}"' -f $msiLogPath)
)
$startProcessParameters = @{
    FilePath = $msiexec
    ArgumentList = $msiArguments
    Wait = $true
    PassThru = $true
}
$msiProcess = Start-Process @startProcessParameters
$exitCode = $msiProcess.ExitCode
Write-Output "WIREGUARD_MSI_EXIT_CODE=$exitCode"
Write-Output "WIREGUARD_MSI_LOG=$msiLogPath"
if ($exitCode -ne 0 -and $exitCode -ne 3010) {
    throw "WireGuard MSI installation failed with exit code $exitCode. Log: $msiLogPath"
}

$installedExecutable = Get-WireGuardExecutable
if (-not $installedExecutable) {
    throw 'WireGuard installation completed but wireguard.exe was not found.'
}

Write-Output "WIREGUARD_INSTALLED=$installedExecutable"
if ($exitCode -eq 3010) {
    Write-Output 'WIREGUARD_REBOOT_RECOMMENDED=1'
}
