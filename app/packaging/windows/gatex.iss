; Inno Setup script for the Windows installer. CI passes /DAppVersion,
; /DIconFile and /DSourceDir (the flutter Release folder with gatex-core.exe
; and wintun.dll).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6E7C1F2A-5B4D-4C8E-9A61-0F3D2B7C9E14}
AppName=GateX VPN
AppVersion={#AppVersion}
AppPublisher=GateX
AppPublisherURL=https://gatexx.ru
AppSupportURL=https://t.me/gatexvpn_support
DefaultDirName={autopf}\GateX
DefaultGroupName=GateX
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=GateX-Setup-{#AppVersion}
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\gatex.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=force

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\GateX VPN"; Filename: "{app}\gatex.exe"
Name: "{autodesktop}\GateX VPN"; Filename: "{app}\gatex.exe"; Tasks: desktopicon

[Registry]
; gatex:// links from the bot open the app with the link as an argument.
Root: HKCR; Subkey: "gatex"; ValueType: string; ValueName: ""; ValueData: "URL:GateX"; Flags: uninsdeletekey
Root: HKCR; Subkey: "gatex"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "gatex\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\gatex.exe,0"
Root: HKCR; Subkey: "gatex\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\gatex.exe"" ""%1"""

[Run]
Filename: "{app}\gatex.exe"; Description: "{cm:LaunchProgram,GateX VPN}"; Flags: nowait postinstall skipifsilent shellexec

[UninstallRun]
Filename: "schtasks"; Parameters: "/Delete /TN ""GateX VPN"" /F"; Flags: runhidden; RunOnceId: "DropAutostart"
Filename: "taskkill"; Parameters: "/F /IM gatex-core.exe"; Flags: runhidden; RunOnceId: "KillCore"
Filename: "taskkill"; Parameters: "/F /IM gatex.exe"; Flags: runhidden; RunOnceId: "KillApp"
