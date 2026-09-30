@echo off
setlocal EnableExtensions
title WireGuard MFA Client Cleanup

fltmc >nul 2>&1
if errorlevel 1 (
  echo Requesting administrator privileges...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo.
echo ============================================================
echo  WireGuard MFA Client - Complete Local Cleanup
echo ============================================================
echo.
echo This removes:
echo   - WireGuard MFA Client application files
echo   - Tunnel services whose names start with wgmfa_
echo   - Protected tunnel configurations and provisioning logs
echo   - Current user's saved server settings and device identity
echo   - MFA Client WebView2 cookies, sessions, and cache
echo.
echo WireGuard for Windows itself and unrelated tunnels are kept.
echo Server-side registered device records are NOT removed.
echo.
choice /C YN /N /M "Continue? [Y/N]: "
if errorlevel 2 exit /b 0

echo.
echo [1/6] Stopping WireGuard MFA Client...
taskkill /F /IM wireguard_mfa_client.exe >nul 2>&1

echo [2/6] Running the installed uninstaller when available...
if exist "%ProgramFiles%\WireGuard MFA Client\uninstall.exe" (
  start "" /wait "%ProgramFiles%\WireGuard MFA Client\uninstall.exe" /S
)

echo [3/6] Removing MFA Client tunnel services...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$wg = Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe';" ^
  "if (Test-Path -LiteralPath $wg) {" ^
  "  Get-Service -Name 'WireGuardTunnel$wgmfa_*' -ErrorAction SilentlyContinue | ForEach-Object {" ^
  "    $name = $_.Name.Substring('WireGuardTunnel$'.Length);" ^
  "    Write-Host ('Removing tunnel: ' + $name);" ^
  "    $process = Start-Process -FilePath $wg -ArgumentList @('/uninstalltunnelservice', $name) -Wait -PassThru;" ^
  "    if ($process.ExitCode -ne 0) { Write-Warning ('Removal failed: ' + $name) }" ^
  "  }" ^
  "} else { Write-Warning 'WireGuard executable was not found.' }"

echo [4/6] Removing application data...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$paths = @(" ^
  "  (Join-Path $env:ProgramFiles 'WireGuard MFA Client')," ^
  "  (Join-Path $env:ProgramData 'WireGuard MFA Client')," ^
  "  (Join-Path $env:APPDATA 'jp.co.fairway\WireGuard MFA Client')," ^
  "  (Join-Path $env:LOCALAPPDATA 'flutter_webview_windows\wireguard_mfa_client')," ^
  "  (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\WireGuard MFA Client')," ^
  "  (Join-Path $env:PUBLIC 'Desktop\WireGuard MFA Client.lnk')" ^
  ");" ^
  "foreach ($path in $paths) {" ^
  "  if (Test-Path -LiteralPath $path) {" ^
  "    Write-Host ('Removing: ' + $path);" ^
  "    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Continue" ^
  "  }" ^
  "}"

echo [5/6] Removing stale uninstall registration...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Remove-Item -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WireGuardMfaClient' -Recurse -Force -ErrorAction SilentlyContinue"

echo [6/6] Checking for remaining WireGuard tunnels...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$services = Get-Service -Name 'WireGuardTunnel$*' -ErrorAction SilentlyContinue;" ^
  "if ($services) {" ^
  "  Write-Host 'Remaining WireGuard tunnels were NOT removed:' -ForegroundColor Yellow;" ^
  "  $services | Select-Object Name, Status, DisplayName | Format-Table -AutoSize" ^
  "} else { Write-Host 'No WireGuard tunnel services remain.' -ForegroundColor Green }"

echo.
echo Local cleanup completed.
echo.
echo IMPORTANT:
echo Delete or allow re-registration of this PC in the WebAdmin
echo Registered MFA Devices screen before installing the client again.
echo.
pause
endlocal
