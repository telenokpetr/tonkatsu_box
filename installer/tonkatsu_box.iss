#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Own AppId: this build installs next to the official Tonkatsu Box, not over it.
AppId={{B7D3C2E4-6A51-4F0B-9D3E-2C1A7F5E8B90}
AppName=Tonkatsu Box Watch
AppVersion={#AppVersion}
AppPublisher=telenokpetr
DefaultDirName={autopf}\Tonkatsu Box Watch
DefaultGroupName=Tonkatsu Box Watch
; Per-user install: no admin prompt, and the app keeps its data in %APPDATA%.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\tonkatsu_box.exe
OutputDir=..\dist
OutputBaseFilename=tonkatsu-box-watch-setup

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Tonkatsu Box Watch"; Filename: "{app}\tonkatsu_box.exe"
Name: "{autodesktop}\Tonkatsu Box Watch"; Filename: "{app}\tonkatsu_box.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\tonkatsu_box.exe"; Description: "{cm:LaunchProgram,Tonkatsu Box Watch}"; Flags: nowait postinstall skipifsilent
