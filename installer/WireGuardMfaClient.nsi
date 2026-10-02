Unicode True
RequestExecutionLevel admin
SetCompressor /SOLID zlib

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

!ifndef APP_VERSION
  !define APP_VERSION "1.0.0"
!endif

!define APP_NAME "WireGuard MFA Client"
!define APP_EXE "wireguard_mfa_client.exe"
!define COMPANY_NAME "Fairway"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\WireGuardMfaClient"

Name "${APP_NAME}"
OutFile "..\dist\installer\WireGuardMfaClient-${APP_VERSION}-windows-x64-setup.exe"
InstallDir "$PROGRAMFILES64\WireGuard MFA Client"
InstallDirRegKey HKLM "${UNINSTALL_KEY}" "InstallLocation"
Icon "..\windows\runner\resources\app_icon.ico"
UninstallIcon "..\windows\runner\resources\app_icon.ico"
BrandingText "${APP_NAME}"

!define MUI_ABORTWARNING
!define MUI_ICON "..\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\windows\runner\resources\app_icon.ico"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Japanese"

Section "Install"
  SetShellVarContext all
  DetailPrint "WireGuard MFA Client installer ${APP_VERSION}"
  SetOutPath "$INSTDIR"
  File /r "..\build\windows\x64\runner\Release\*"
  SetOutPath "$INSTDIR\installer"
  File "configure_tunnel.ps1"
  File "provision_tunnel.ps1"
  File "uninstall_tunnels.ps1"
  File "install_wireguard.ps1"

  InitPluginsDir
  File /oname=$PLUGINSDIR\vc_redist.x64.exe "prerequisites\vc_redist.x64.exe"
  File /oname=$PLUGINSDIR\MicrosoftEdgeWebview2Setup.exe "prerequisites\MicrosoftEdgeWebview2Setup.exe"
  File /oname=$PLUGINSDIR\wireguard-amd64-1.1.1.msi "prerequisites\wireguard-amd64-1.1.1.msi"

  DetailPrint "Microsoft Visual C++ Runtimeを確認しています..."
  nsExec::ExecToLog '$\"$PLUGINSDIR\vc_redist.x64.exe$\" /install /quiet /norestart'
  Pop $0
  ${If} $0 == 3010
    SetRebootFlag true
  ${ElseIf} $0 != 0
  ${AndIf} $0 != 1638
    MessageBox MB_ICONSTOP "Microsoft Visual C++ Runtimeのインストールに失敗しました（終了コード: $0）。"
    Abort
  ${EndIf}

  DetailPrint "Microsoft Edge WebView2 Runtimeを確認しています..."
  nsExec::ExecToLog '$\"$PLUGINSDIR\MicrosoftEdgeWebview2Setup.exe$\" /silent /install'
  Pop $0
  ${If} $0 == 3010
    SetRebootFlag true
  ${ElseIf} $0 != 0
  ${AndIf} $0 != 1638
    MessageBox MB_ICONEXCLAMATION "Microsoft Edge WebView2 Runtimeを導入できませんでした（終了コード: $0）。認証時は既定ブラウザーを使用します。"
  ${EndIf}

  SetRegView 64
  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "Publisher" "${COMPANY_NAME}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\uninstall.exe$\"'
  WriteRegStr HKLM "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\uninstall.exe$\" /S'
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "EstimatedSize" $0

  DetailPrint "WireGuard for Windowsを確認しています..."
  System::Call 'Kernel32::SetEnvironmentVariable(t "WGMFA_WIREGUARD_MSI", t "$PLUGINSDIR\wireguard-amd64-1.1.1.msi") i .r1'
  ${If} $1 = 0
    MessageBox MB_ICONSTOP "WireGuard MSIをセットアップ処理へ渡せませんでした。MFA ClientはWindowsの設定から削除できます。"
    Abort
  ${EndIf}
  nsExec::ExecToLog '$\"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe$\" -NoProfile -ExecutionPolicy Bypass -File $\"$INSTDIR\installer\install_wireguard.ps1$\"'
  Pop $0
  System::Call 'Kernel32::SetEnvironmentVariable(t "WGMFA_WIREGUARD_MSI", p 0)'
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "WireGuardのインストールに失敗しました（終了コード: $0）。MFA ClientはWindowsの設定から削除できます。"
    Abort
  ${EndIf}

SectionEnd

Section "Uninstall"
  SetShellVarContext all
  SetRegView 64
  nsExec::ExecToLog '$\"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe$\" -NoProfile -ExecutionPolicy Bypass -File $\"$INSTDIR\installer\uninstall_tunnels.ps1$\"'
  Pop $0
  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APP_NAME}"
  DeleteRegKey HKLM "${UNINSTALL_KEY}"
  RMDir /r "$INSTDIR"
SectionEnd
