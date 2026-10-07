[CmdletBinding()]
param(
    [string]$Version = '1.0.0',
    [int]$BuildNumber = 22,
    [string]$Flutter = 'C:\Users\kudo\Documents\Codex\tools\flutter\bin\flutter.bat',
    [string]$AndroidSdk = 'C:\Users\kudo\Documents\Codex\tools\android-sdk',
    [string]$KeyTool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
    [string]$SigningDirectory = (Join-Path $env:LOCALAPPDATA 'WireGuardMfaClient\signing'),
    [string]$BuildRoot = 'C:\wgmfa_android_release'
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $BuildNumber -lt 22) { throw 'Use a semantic version and versionCode >= 22.' }
$source = Split-Path -Parent $PSScriptRoot
$keyPath = Join-Path $SigningDirectory 'android-release.jks'
$credentialPath = Join-Path $SigningDirectory 'android-release-password.clixml'
foreach ($file in @($Flutter, $KeyTool, $keyPath, $credentialPath)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required file missing: $file" }
}
$buildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $buildTools) { throw 'Android SDK build-tools not found.' }
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
$aapt = Join-Path $buildTools.FullName 'aapt.exe'
$output = Join-Path $source "dist\android\$Version"
if (Test-Path -LiteralPath $output) { throw 'Release output already exists. Do not overwrite reviewed artifacts.' }
$notes = Join-Path $source "releases\android-v$Version.md"
if (-not (Test-Path -LiteralPath $notes)) { throw 'Version-specific release notes are required.' }
$build = Join-Path $BuildRoot ([guid]::NewGuid().ToString('N').Substring(0, 12))
if ([IO.Path]::GetFullPath($build).StartsWith([IO.Path]::GetFullPath($source), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BuildRoot must be outside the source checkout.'
}
New-Item -ItemType Directory -Path $build -Force | Out-Null
& robocopy $source $build /E /XD .git .dart_tool build dist .idea .vscode /XF *.jks *.keystore *.p12 *.clixml key.properties /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'Source copy failed.' }
$credential = Import-Clixml -LiteralPath $credentialPath
$names = @('WGMFA_KEYSTORE', 'WGMFA_STORE_PASSWORD', 'WGMFA_KEY_ALIAS', 'WGMFA_KEY_PASSWORD', 'JAVA_HOME')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:WGMFA_KEYSTORE = $keyPath
    $env:WGMFA_KEY_ALIAS = $credential.UserName
    $env:WGMFA_STORE_PASSWORD = $credential.GetNetworkCredential().Password
    $env:WGMFA_KEY_PASSWORD = $env:WGMFA_STORE_PASSWORD
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $KeyTool)
    Push-Location $build
    try {
        & $Flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'Analysis failed.' }
        & $Flutter test
        if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
        & $Flutter build apk --release --build-name $Version --build-number $BuildNumber
        if ($LASTEXITCODE -ne 0) { throw 'Release APK build failed.' }
        $apk = Join-Path $build 'build\app\outputs\flutter-apk\app-release.apk'
        $certificate = Join-Path $build 'android-release-certificate.der'
        & $KeyTool -exportcert -keystore $keyPath -alias $env:WGMFA_KEY_ALIAS -file $certificate -storepass:env WGMFA_STORE_PASSWORD
        if ($LASTEXITCODE -ne 0) { throw 'Certificate export failed.' }
        $expected = (Get-FileHash -LiteralPath $certificate -Algorithm SHA256).Hash.ToLowerInvariant()
        $signature = & $apksigner verify --verbose --print-certs $apk 2>&1
        if ($LASTEXITCODE -ne 0 -or ($signature -join "`n") -notmatch [regex]::Escape($expected)) { throw 'APK signature does not match the release key.' }
        $badging = & $aapt dump badging $apk 2>&1
        if ($LASTEXITCODE -ne 0 -or ($badging -join "`n") -match 'application-debuggable' -or
            ($badging -join "`n") -notmatch "versionCode='$BuildNumber' versionName='$([regex]::Escape($Version))'") {
            throw 'APK version or release flags failed verification.'
        }
        New-Item -ItemType Directory -Path $output -Force | Out-Null
        $name = "WireGuardMfaClient-android-$Version.apk"
        Copy-Item -LiteralPath $apk -Destination (Join-Path $output $name)
        Copy-Item -LiteralPath $certificate -Destination $output
        $signature | Set-Content -LiteralPath (Join-Path $output 'signature-verification.txt') -Encoding utf8
        $badging | Set-Content -LiteralPath (Join-Path $output 'apk-metadata.txt') -Encoding utf8
        $hash = (Get-FileHash -LiteralPath (Join-Path $output $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $name" | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii
        Copy-Item -LiteralPath $notes -Destination (Join-Path $output 'RELEASE_NOTES.md')
        Write-Host "Release artifacts: $output"
        Write-Host "Certificate SHA-256: $expected"
        & (Join-Path $source 'tool\package_android_release.ps1') -Version $Version
    } finally { Pop-Location }
} finally {
    if (Test-Path -LiteralPath (Join-Path $build 'android\gradlew.bat')) {
        & (Join-Path $build 'android\gradlew.bat') --stop | Out-Null
    }
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
