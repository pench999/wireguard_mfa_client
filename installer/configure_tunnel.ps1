[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$TunnelUser
)

$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'トンネルの登録には管理者権限が必要です。'
    }
}

function Get-WireGuardExecutable {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

    if (-not $candidates) {
        throw 'WireGuard for Windowsが見つかりません。先に公式WireGuardをインストールしてください。'
    }
    return $candidates[0]
}

function Grant-TunnelServiceControl {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [Parameter(Mandatory = $true)][string]$AccountName
    )

    $sid = ([Security.Principal.NTAccount]::new($AccountName)).Translate(
        [Security.Principal.SecurityIdentifier]
    )
    $sddlOutput = & "$env:SystemRoot\System32\sc.exe" sdshow $ServiceName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "サービスのアクセス権を取得できません: $($sddlOutput -join ' ')"
    }

    $sddl = ($sddlOutput | Where-Object { $_ -match '^[OGDS]:' } | Select-Object -First 1).Trim()
    if (-not $sddl) {
        throw 'サービスのセキュリティ記述子を解析できません。'
    }

    $descriptor = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
    if (-not $descriptor.DiscretionaryAcl) {
        $descriptor.DiscretionaryAcl = [Security.AccessControl.RawAcl]::new(2, 1)
    }

    # Query status, start, stop, interrogate, user-defined control, and read control.
    $serviceAccessMask = 0x000201B4
    $ace = [Security.AccessControl.CommonAce]::new(
        [Security.AccessControl.AceFlags]::None,
        [Security.AccessControl.AceQualifier]::AccessAllowed,
        $serviceAccessMask,
        $sid,
        $false,
        $null
    )
    $descriptor.DiscretionaryAcl.InsertAce($descriptor.DiscretionaryAcl.Count, $ace)

    $updatedSddl = $descriptor.GetSddlForm([Security.AccessControl.AccessControlSections]::All)
    $result = & "$env:SystemRoot\System32\sc.exe" sdset $ServiceName $updatedSddl 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "サービスのアクセス権を設定できません: $($result -join ' ')"
    }
}

Assert-Administrator

$resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
if ([IO.Path]::GetExtension($resolvedConfig) -ine '.conf') {
    throw 'WireGuard設定ファイル（.conf）を指定してください。'
}

$tunnelName = [IO.Path]::GetFileNameWithoutExtension($resolvedConfig)
if ($tunnelName -notmatch '^[A-Za-z0-9_.=+-]{1,64}$') {
    throw '設定ファイル名には英数字と _ . = + - のみ使用できます。'
}

$wireGuard = Get-WireGuardExecutable
$serviceName = 'WireGuardTunnel$' + $tunnelName
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    $installOutput = & $wireGuard /installtunnelservice $resolvedConfig 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "WireGuardトンネルサービスを登録できません: $($installOutput -join ' ')"
    }
    $service = Get-Service -Name $serviceName -ErrorAction Stop
}

Grant-TunnelServiceControl -ServiceName $serviceName -AccountName $TunnelUser
Write-Output "TUNNEL_NAME=$tunnelName"
Write-Output "SERVICE_NAME=$serviceName"

