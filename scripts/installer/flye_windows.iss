; ============================================================================
; Flye for Windows (native port) - one-click installer
;
; Builds a single self-contained Setup .exe that bundles:
;   * the static flye-modules / flye-minimap2 / flye-samtools .exe (no MinGW DLLs)
;   * the Flye Python package (flye\) + bundled toy test data
;   * an embedded Python 3.11 (no system Python needed)
;   * a graphical front-end (gui\) + a "Flye Command Prompt" + a `flye` launcher
;
; Invoked by build_flye_installer.ps1, which passes the payload location:
;   ISCC.exe /DPayloadDir=<dir> /DOutputDir=<dir> /DAppVersion=<ver> flye_windows.iss
;
; Per-user install by default (no admin), can elevate to all-users.
; ============================================================================

#ifndef PayloadDir
  #define PayloadDir "..\..\..\flye-dist\payload"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef AppVersion
  #define AppVersion "2.9.6"
#endif

#define MyAppName "Flye for Windows"
#define MyAppPublisher "Flye native-Windows port"
#define MyAppURL "https://github.com/MrMufasii/Flye-for-Windows"

[Setup]
AppId={{D7E2F1B4-3C6A-4F1E-9A2B-7C4D5E6F8A91}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\Flye-Windows
DefaultGroupName=Flye for Windows
DisableProgramGroupPage=yes
DisableDirPage=no
LicenseFile={#PayloadDir}\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=Flye-Windows-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
ChangesEnvironment=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={sys}\cmd.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut for the Flye app"; GroupDescription: "Shortcuts:"
Name: "addtopath"; Description: "Add Flye to my PATH (run 'flye' from any terminal)"; GroupDescription: "Integration:"

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; Graphical app (primary entry point for non-technical users) - launched console-less via the VBS shim.
Name: "{group}\Flye for Windows (app)"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\gui\Flye-GUI.vbs"""; WorkingDir: "{app}\gui"; IconFilename: "{sys}\shell32.dll"; IconIndex: 13; Comment: "Assemble long reads with a simple graphical interface"
Name: "{autodesktop}\Flye for Windows"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\gui\Flye-GUI.vbs"""; WorkingDir: "{app}\gui"; IconFilename: "{sys}\shell32.dll"; IconIndex: 13; Tasks: desktopicon
Name: "{group}\Flye Command Prompt"; Filename: "{app}\flye-shell.bat"; WorkingDir: "{userdocs}"; IconFilename: "{sys}\cmd.exe"; Comment: "Open a terminal with Flye ready to use"
Name: "{group}\Flye Read Me"; Filename: "{app}\README-WINDOWS.txt"
Name: "{group}\Uninstall Flye"; Filename: "{uninstallexe}"

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\gui\Flye-GUI.vbs"""; Description: "Launch the Flye app now"; Flags: postinstall skipifsilent nowait
Filename: "{app}\flye-shell.bat"; Description: "Open the Flye Command Prompt instead"; Flags: postinstall skipifsilent nowait unchecked

[Code]
const EnvironmentKey = 'Environment';

function PathContains(const Paths, Dir: string): Boolean;
begin
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Paths) + ';') > 0;
end;

procedure AddToUserPath(const Dir: string);
var
  Paths: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths) then
    Paths := '';
  if PathContains(Paths, Dir) then
    exit;
  if (Paths <> '') and (Paths[Length(Paths)] <> ';') then
    Paths := Paths + ';';
  Paths := Paths + Dir;
  RegWriteExpandStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths);
end;

procedure RemoveFromUserPath(const Dir: string);
var
  Paths, Rebuilt, Part: string;
  P: Integer;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths) then
    exit;
  if not PathContains(Paths, Dir) then
    exit;
  Rebuilt := '';
  Paths := Paths + ';';
  repeat
    P := Pos(';', Paths);
    Part := Copy(Paths, 1, P - 1);
    Paths := Copy(Paths, P + 1, Length(Paths));
    if (Part <> '') and (Uppercase(Part) <> Uppercase(Dir)) then
    begin
      if Rebuilt <> '' then
        Rebuilt := Rebuilt + ';';
      Rebuilt := Rebuilt + Part;
    end;
  until Paths = '';
  RegWriteExpandStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Rebuilt);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    if WizardIsTaskSelected('addtopath') then
      AddToUserPath(ExpandConstant('{app}\bin'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveFromUserPath(ExpandConstant('{app}\bin'));
end;
