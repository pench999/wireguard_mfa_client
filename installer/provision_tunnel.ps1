[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$TunnelUser
)

$ErrorActionPreference = 'Stop'
$logDirectory = Join-Path $env:ProgramData 'WireGuard MFA Client'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logPath = Join-Path $logDirectory 'provision.log'
Start-Transcript -Path $logPath -Append -Force | Out-Null
Write-Output "PROVISION_STARTED=$(Get-Date -Format o)"

function Get-WireGuardExecutable {
    foreach ($directory in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Select-Object -Unique) {
        $candidate = Join-Path $directory 'WireGuard\wireguard.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'WireGuard for Windows was not found.'
}

function Grant-TunnelServiceControl {
    param([string]$ServiceName, [string]$AccountName)
    $sid = ([Security.Principal.NTAccount]::new($AccountName)).Translate([Security.Principal.SecurityIdentifier])
    $output = & "$env:SystemRoot\System32\sc.exe" sdshow $ServiceName 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to read service ACL: $($output -join ' ')" }
    $sddl = ($output | Where-Object { $_ -match '^[OGDS]:' } | Select-Object -First 1).Trim()
    $descriptor = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
    $ace = [Security.AccessControl.CommonAce]::new(
        [Security.AccessControl.AceFlags]::None,
        [Security.AccessControl.AceQualifier]::AccessAllowed,
        0x000201B4,
        $sid,
        $false,
        $null
    )
    $descriptor.DiscretionaryAcl.InsertAce($descriptor.DiscretionaryAcl.Count, $ace)
    $result = & "$env:SystemRoot\System32\sc.exe" sdset $ServiceName $descriptor.GetSddlForm([Security.AccessControl.AccessControlSections]::All) 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to update service ACL: $($result -join ' ')" }
}

function Stop-TunnelService {
    param([Parameter(Mandatory = $true)][string]$ServiceName)

    Set-Service -Name $ServiceName -StartupType Manual
    $lastStopOutput = @()
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        if ($service.Status -eq 'Stopped') { return }
        if ($service.Status -notin @('StartPending', 'StopPending')) {
            $lastStopOutput = & "$env:SystemRoot\System32\sc.exe" stop $ServiceName 2>&1
        }
        Start-Sleep -Milliseconds 500
    }

    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    throw "WireGuard tunnel service did not stop ($($service.Status)): $ServiceName $($lastStopOutput -join ' ')"
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator privileges are required.'
}
if ($TunnelUser -eq '' -or $TunnelUser.EndsWith('\')) { throw 'The Windows account is invalid.' }
$resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
$tunnelName = [IO.Path]::GetFileNameWithoutExtension($resolvedConfig)
if ($tunnelName -notmatch '^[A-Za-z0-9_.=+-]{1,64}$') { throw 'The tunnel name is invalid.' }

$wireGuard = Get-WireGuardExecutable
$serviceName = 'WireGuardTunnel$' + $tunnelName
$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($existing) {
    & $wireGuard /uninstalltunnelservice $tunnelName | Out-Null
    for ($attempt = 0; $attempt -lt 30 -and (Get-Service -Name $serviceName -ErrorAction SilentlyContinue); $attempt++) {
        Start-Sleep -Milliseconds 250
    }
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) { throw 'The existing tunnel could not be replaced.' }
}

$configDirectory = Join-Path $env:ProgramData 'WireGuard MFA Client\Configurations'
New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
& "$env:SystemRoot\System32\icacls.exe" $configDirectory /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to protect the configuration directory.' }
$storedConfig = Join-Path $configDirectory ($tunnelName + '.conf')
Copy-Item -LiteralPath $resolvedConfig -Destination $storedConfig -Force
& "$env:SystemRoot\System32\icacls.exe" $storedConfig /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to protect the configuration file.' }

try {
    $process = Start-Process -FilePath $wireGuard -ArgumentList @('/installtunnelservice', ('"{0}"' -f $storedConfig)) -Wait -PassThru
    for ($attempt = 0; $attempt -lt 30 -and -not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue); $attempt++) {
        Start-Sleep -Milliseconds 250
    }
    if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
        throw "WireGuard tunnel installation failed with exit code $($process.ExitCode)."
    }
    Stop-TunnelService -ServiceName $serviceName
    Grant-TunnelServiceControl -ServiceName $serviceName -AccountName $TunnelUser
    Write-Output "PROVISION_COMPLETED=$serviceName"
} catch {
    Write-Error $_
    Remove-Item -LiteralPath $storedConfig -Force -ErrorAction SilentlyContinue
    throw
}
