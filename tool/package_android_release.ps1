#Requires -Version 7.2
[CmdletBinding()]
param([string]$Version = '1.0.0')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid version.' }
$source = Split-Path -Parent $PSScriptRoot
$release = Join-Path $source "dist\android\$Version"
$apk = Join-Path $release "WireGuardMfaClient-android-$Version.apk"
$bundle = Join-Path $source "dist\android\WireGuardMfaClient-android-$Version.zip"
if (Test-Path -LiteralPath $bundle) { throw 'A reviewed release bundle must not be overwritten.' }
if (-not (Test-Path -LiteralPath $apk)) { throw 'Build the signed release APK first.' }
$licenses = Join-Path $release 'licenses'
New-Item -ItemType Directory -Path $licenses -Force | Out-Null
Copy-Item -Path (Join-Path $source 'licenses\android\*') -Destination $licenses -Recurse -Force
$archive = [IO.Compression.ZipFile]::OpenRead($apk)
try {
    $entry = $archive.GetEntry('assets/flutter_assets/NOTICES.Z')
    if (-not $entry) { throw 'Flutter license notices missing from APK.' }
    $inputStream = $entry.Open()
    $decoded = [IO.Compression.GZipStream]::new($inputStream, [IO.Compression.CompressionMode]::Decompress)
    $outputStream = [IO.File]::Create((Join-Path $licenses 'Flutter-package-NOTICES.txt'))
    try { $decoded.CopyTo($outputStream) } finally { $outputStream.Dispose(); $decoded.Dispose(); $inputStream.Dispose() }
    foreach ($license in ($archive.Entries | Where-Object { $_.FullName -match '^META-INF/.+/LICENSE\.txt$' })) {
        $name = $license.FullName.Replace('/', '_')
        [IO.Compression.ZipFileExtensions]::ExtractToFile($license, (Join-Path $licenses $name), $true)
    }
} finally { $archive.Dispose() }
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $bundle -CompressionLevel Optimal
$checksum = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
"$checksum  $([IO.Path]::GetFileName($bundle))" | Set-Content -LiteralPath ($bundle + '.sha256') -Encoding ascii
Write-Host "Distribution bundle: $bundle"
