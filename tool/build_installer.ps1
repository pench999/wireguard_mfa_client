[CmdletBinding()]
param(
    [string]$Flutter = '',
    [string]$MakeNsis = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
$versionLine = $pubspec | Where-Object { $_ -match '^version:\s*([^+\s]+)' } | Select-Object -First 1
if (-not $versionLine -or $versionLine -notmatch '^version:\s*([^+\s]+)') {
    throw 'pubspec.yamlからバージョンを取得できません。'
}
$appVersion = $Matches[1]

if (-not $Flutter) {
    $flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        $Flutter = $flutterCommand.Source
    }
}
if (-not $Flutter -or -not (Test-Path -LiteralPath $Flutter -PathType Leaf)) {
    throw "Flutterが見つかりません: $Flutter"
}

if (-not $MakeNsis) {
    $makeNsisCommand = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($makeNsisCommand) {
        $MakeNsis = $makeNsisCommand.Source
    } else {
        $defaultMakeNsis = Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe'
        if (Test-Path -LiteralPath $defaultMakeNsis -PathType Leaf) {
            $MakeNsis = $defaultMakeNsis
        }
    }
}
if (-not $MakeNsis -or -not (Test-Path -LiteralPath $MakeNsis -PathType Leaf)) {
    throw 'NSISのmakensis.exeが見つかりません。NSISをインストールするか-MakeNsisで指定してください。'
}

Push-Location $projectRoot
try {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub getに失敗しました。' }

    & $Flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyzeに失敗しました。' }

    & $Flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter testに失敗しました。' }

    & $Flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windowsリリースビルドに失敗しました。' }

    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'dist\installer') -Force | Out-Null
    & $MakeNsis '/INPUTCHARSET' 'UTF8' "/DAPP_VERSION=$appVersion" (Join-Path $projectRoot 'installer\WireGuardMfaClient.nsi')
    if ($LASTEXITCODE -ne 0) { throw 'インストーラーのコンパイルに失敗しました。' }
} finally {
    Pop-Location
}
