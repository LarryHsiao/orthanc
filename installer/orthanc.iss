; Orthanc — Inno Setup script
; Ported from Heimdall's installer/heimdall.iss.
; Compile from the repo root with:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\orthanc.iss
; Output lands in build\installer\.

#define MyAppName        "Orthanc"
; Version is supplied by the build script via ISCC /DMyAppVersion=<pubspec version>.
; The literal below is only a fallback for a bare local compile with no define.
#ifndef MyAppVersion
  #define MyAppVersion   "1.0.0"
#endif
#define MyAppPublisher   "Larry Hsiao"
#define MyAppURL         "https://github.com/LarryHsiao/orthanc"
#define MyAppExeName     "orthanc.exe"
#define MyAppSourceDir   "..\build\windows\x64\runner\Release"
#define MyAppOutputDir   "..\build\installer"

[Setup]
; A fixed GUID — keep this constant across versions so upgrades replace cleanly.
; Distinct from Heimdall's own AppId — each product needs its own.
AppId={{2E088924-E975-4441-82D1-31CB4A08E22E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
OutputDir={#MyAppOutputDir}
OutputBaseFilename=orthanc-setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSourceDir}\*.dll";            DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSourceDir}\data\*";           DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}";              Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}";        Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
