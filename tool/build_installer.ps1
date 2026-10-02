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
$wireGuardMsi = Join-Path $projectRoot 'installer\prerequisites\wireguard-amd64-1.1.1.msi'
$wireGuardHash = '7BFED60AD61B785C914B38B61555A975488E1D3EC472DBFB2FCDF498FCA75242'
$visualCppInstaller = Join-Path $projectRoot 'installer\prerequisites\vc_redist.x64.exe'
$visualCppHash = 'CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B'
$webViewInstaller = Join-Path $projectRoot 'installer\prerequisites\MicrosoftEdgeWebView2RuntimeInstallerX64.exe'
$webViewInstallerHash = 'F6DF8E4BC857786FF641CD01DA1449169EAF8236C936CED485EA61685BA4DA40'

if (-not (Test-Path -LiteralPath $wireGuardMsi -PathType Leaf)) {
    throw "WireGuard MSIが見つかりません: $wireGuardMsi"
}
$actualWireGuardHash = (Get-FileHash -LiteralPath $wireGuardMsi -Algorithm SHA256).Hash
if ($actualWireGuardHash -ne $wireGuardHash) {
    throw "WireGuard MSIのSHA-256が一致しません: $actualWireGuardHash"
}
$wireGuardSignature = Get-AuthenticodeSignature -LiteralPath $wireGuardMsi
if ($wireGuardSignature.Status -ne 'Valid' -or
    -not $wireGuardSignature.SignerCertificate.Subject.Contains('O=WireGuard LLC')) {
    throw "WireGuard MSIの署名が無効です: $($wireGuardSignature.Status)"
}

if (-not (Test-Path -LiteralPath $visualCppInstaller -PathType Leaf)) {
    throw "Visual C++ Runtimeが見つかりません: $visualCppInstaller"
}
$actualVisualCppHash = (Get-FileHash -LiteralPath $visualCppInstaller -Algorithm SHA256).Hash
if ($actualVisualCppHash -ne $visualCppHash) {
    throw "Visual C++ RuntimeのSHA-256が一致しません: $actualVisualCppHash"
}
$visualCppSignature = Get-AuthenticodeSignature -LiteralPath $visualCppInstaller
if ($visualCppSignature.Status -ne 'Valid' -or
    -not $visualCppSignature.SignerCertificate.Subject.Contains('O=Microsoft Corporation')) {
    throw "Visual C++ Runtimeの署名が無効です: $($visualCppSignature.Status)"
}

if (-not (Test-Path -LiteralPath $webViewInstaller -PathType Leaf)) {
    throw "WebView2 Standalone Installerが見つかりません: $webViewInstaller"
}
$actualWebViewHash = (Get-FileHash -LiteralPath $webViewInstaller -Algorithm SHA256).Hash
if ($actualWebViewHash -ne $webViewInstallerHash) {
    throw "WebView2 Standalone InstallerのSHA-256が一致しません: $actualWebViewHash"
}
$webViewSignature = Get-AuthenticodeSignature -LiteralPath $webViewInstaller
if ($webViewSignature.Status -ne 'Valid' -or
    -not $webViewSignature.SignerCertificate.Subject.Contains('O=Microsoft Corporation')) {
    throw "WebView2 Standalone Installerの署名が無効です: $($webViewSignature.Status)"
}

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
