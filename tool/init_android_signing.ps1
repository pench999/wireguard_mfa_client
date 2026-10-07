[CmdletBinding()]
param(
    [string]$SigningDirectory = (Join-Path $env:LOCALAPPDATA 'WireGuardMfaClient\signing'),
    [string]$KeyTool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $KeyTool -PathType Leaf)) { throw 'Set -KeyTool to the JDK keytool.exe path.' }
$keyPath = Join-Path $SigningDirectory 'android-release.jks'
$credentialPath = Join-Path $SigningDirectory 'android-release-password.clixml'
if ((Test-Path -LiteralPath $keyPath) -or (Test-Path -LiteralPath $credentialPath)) {
    throw 'Signing material already exists. Never overwrite a release signing key.'
}
New-Item -ItemType Directory -Path $SigningDirectory -Force | Out-Null
$acl = Get-Acl -LiteralPath $SigningDirectory
$acl.SetAccessRuleProtection($true, $false)
foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        [Security.Principal.SecurityIdentifier]::new($sid), 'FullControl',
        'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $SigningDirectory -AclObject $acl
$bytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$password = [Convert]::ToBase64String($bytes)
$credential = [PSCredential]::new('wgmfa-release', (ConvertTo-SecureString $password -AsPlainText -Force))
$credential | Export-Clixml -LiteralPath $credentialPath
$previous = $env:WGMFA_INIT_PASSWORD
try {
    $env:WGMFA_INIT_PASSWORD = $password
    & $KeyTool -genkeypair -noprompt -keystore $keyPath -storetype JKS -alias wgmfa-release `
        -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=WireGuard MFA Client Android' `
        -storepass:env WGMFA_INIT_PASSWORD -keypass:env WGMFA_INIT_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Release keystore creation failed. Inspect the directory before retrying.' }
} finally {
    $env:WGMFA_INIT_PASSWORD = $previous
    $password = $null
}
Write-Host "Keystore: $keyPath"
Write-Host "DPAPI-protected password: $credentialPath"
Write-Host 'Back up the keystore and recoverable password separately before distributing an APK.'
