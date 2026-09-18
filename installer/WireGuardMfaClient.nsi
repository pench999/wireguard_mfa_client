Unicode True
RequestExecutionLevel admin
SetCompressor /SOLID zlib

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"

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

Var ConfigPath
Var TunnelUser
Var ConfigText
Var UserText

!define MUI_ABORTWARNING
!define MUI_ICON "..\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\windows\runner\resources\app_icon.ico"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
Page custom TunnelPageCreate TunnelPageLeave
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Japanese"

Function .onInit
  SetRegView 64
  StrCpy $TunnelUser "$%USERDOMAIN%\$%USERNAME%"
FunctionEnd

Function BrowseConfig
  nsDialogs::SelectFileDialog open "$ConfigPath" "WireGuard設定 (*.conf)|*.conf"
  Pop $0
  ${If} $0 != ""
    StrCpy $ConfigPath $0
    ${NSD_SetText} $ConfigText $ConfigPath
  ${EndIf}
FunctionEnd

Function TunnelPageCreate
  !insertmacro MUI_HEADER_TEXT "WireGuard設定" "トンネルサービスと利用者権限を設定します。"
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 0 100% 24u "この端末で使用するWireGuard設定ファイルを指定してください。"
  Pop $0
  ${NSD_CreateText} 0 30u 78% 13u "$ConfigPath"
  Pop $ConfigText
  ${NSD_CreateBrowseButton} 80% 29u 20% 15u "参照..."
  Pop $0
  ${NSD_OnClick} $0 BrowseConfig

  ${NSD_CreateLabel} 0 59u 100% 20u "VPNを利用するWindowsユーザー（ドメイン\ユーザー）"
  Pop $0
  ${NSD_CreateText} 0 80u 100% 13u "$TunnelUser"
  Pop $UserText

  ${NSD_CreateLabel} 0 106u 100% 38u "指定ユーザーには、このトンネルサービスの照会・開始・停止権限だけを付与します。"
  Pop $0
  nsDialogs::Show
FunctionEnd

Function TunnelPageLeave
  ${NSD_GetText} $ConfigText $ConfigPath
  ${NSD_GetText} $UserText $TunnelUser

  ${IfNot} ${FileExists} "$ConfigPath"
    MessageBox MB_ICONSTOP "有効なWireGuard設定ファイルを指定してください。"
    Abort
  ${EndIf}
  ${GetFileExt} "$ConfigPath" $0
  ${If} $0 != "conf"
  ${AndIf} $0 != "CONF"
    MessageBox MB_ICONSTOP "拡張子が.confのWireGuard設定ファイルを指定してください。"
    Abort
  ${EndIf}
  ${If} $TunnelUser == ""
    MessageBox MB_ICONSTOP "VPNを利用するWindowsユーザーを指定してください。"
    Abort
  ${EndIf}
  ${IfNot} ${FileExists} "$PROGRAMFILES64\WireGuard\wireguard.exe"
    MessageBox MB_ICONSTOP "WireGuard for Windowsが見つかりません。先に公式WireGuardをインストールしてください。"
    Abort
  ${EndIf}
FunctionEnd

Section "Install"
  SetShellVarContext all
  DetailPrint "WireGuard MFA Client installer ${APP_VERSION}"
  SetOutPath "$INSTDIR"
  File /r "..\build\windows\x64\runner\Release\*"
  SetOutPath "$INSTDIR\installer"
  File "configure_tunnel.ps1"

  DetailPrint "WireGuardトンネルを登録しています..."
  System::Call 'Kernel32::SetEnvironmentVariable(t "WGMFA_CONFIG_PATH", t "$ConfigPath") i .r1'
  ${If} $1 = 0
    MessageBox MB_ICONSTOP "WireGuard設定パスをセットアップ処理へ渡せませんでした。"
    Abort
  ${EndIf}
  System::Call 'Kernel32::SetEnvironmentVariable(t "WGMFA_TUNNEL_USER", t "$TunnelUser") i .r1'
  ${If} $1 = 0
    MessageBox MB_ICONSTOP "VPN利用者をセットアップ処理へ渡せませんでした。"
    Abort
  ${EndIf}
  nsExec::ExecToLog '$\"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe$\" -NoProfile -ExecutionPolicy Bypass -File $\"$INSTDIR\installer\configure_tunnel.ps1$\"'
  Pop $0
  System::Call 'Kernel32::SetEnvironmentVariable(t "WGMFA_CONFIG_PATH", p 0)'
  System::Call 'Kernel32::SetEnvironmentVariable(t "WGMFA_TUNNEL_USER", p 0)'
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "WireGuardトンネル設定に失敗しました（終了コード: $0）。セットアップログを確認してください。"
    Abort
  ${EndIf}

  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "Publisher" "${COMPANY_NAME}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APP_NAME}"
  DeleteRegKey HKLM "${UNINSTALL_KEY}"
  RMDir /r "$INSTDIR"
SectionEnd
