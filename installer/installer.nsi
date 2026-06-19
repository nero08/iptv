; Deko IPTV - Windows installer (NSIS)
; Build: makensis /DWORKDIR="C:\path\to\repo" installer\installer.nsi

Unicode true
!include "MUI2.nsh"

; WORKDIR is passed from the command line (absolute repo root path)
!ifndef WORKDIR
  !define WORKDIR ".."
!endif

; ---- Metadata ---------------------------------------------------------------
Name "Deko IPTV"
OutFile "${WORKDIR}\deko-iptv-setup.exe"
InstallDir "$PROGRAMFILES64\Deko IPTV"
InstallDirRegKey HKCU "Software\Deko IPTV" ""
RequestExecutionLevel admin
BrandingText "Deko IPTV 1.0"

; ---- Icons ------------------------------------------------------------------
!define MUI_ICON    "${WORKDIR}\app\branding\deko-iptv.ico"
!define MUI_UNICON  "${WORKDIR}\app\branding\deko-iptv.ico"

; ---- Pages ------------------------------------------------------------------
!define MUI_WELCOMEPAGE_TITLE "Installation de Deko IPTV"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\zen_player.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Lancer Deko IPTV"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "French"

; ---- Install ----------------------------------------------------------------
Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${WORKDIR}\app\build\windows\x64\runner\Release\"

  ; Shortcuts
  CreateShortcut "$DESKTOP\Deko IPTV.lnk" \
    "$INSTDIR\zen_player.exe" "" "$INSTDIR\zen_player.exe" 0
  CreateDirectory "$SMPROGRAMS\Deko IPTV"
  CreateShortcut "$SMPROGRAMS\Deko IPTV\Deko IPTV.lnk" \
    "$INSTDIR\zen_player.exe" "" "$INSTDIR\zen_player.exe" 0
  CreateShortcut "$SMPROGRAMS\Deko IPTV\Désinstaller.lnk" \
    "$INSTDIR\Uninstall.exe"

  ; Add/Remove Programs entry
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\DekoIPTV" \
    "DisplayName" "Deko IPTV"
  WriteRegStr HKCU \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\DekoIPTV" \
    "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\DekoIPTV" \
    "DisplayIcon" "$INSTDIR\zen_player.exe"
  WriteRegStr HKCU \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\DekoIPTV" \
    "Publisher" "Deko IPTV"
  WriteRegStr HKCU \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\DekoIPTV" \
    "DisplayVersion" "1.0.0"
SectionEnd

; ---- Uninstall --------------------------------------------------------------
Section "Uninstall"
  RMDir /r "$INSTDIR"
  Delete "$DESKTOP\Deko IPTV.lnk"
  RMDir /r "$SMPROGRAMS\Deko IPTV"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DekoIPTV"
  DeleteRegKey HKCU "Software\Deko IPTV"
SectionEnd
