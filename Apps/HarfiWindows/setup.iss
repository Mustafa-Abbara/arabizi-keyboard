; Harfi-Setup.exe: the Windows package as one file to download and double-click, built by windows.yml with Inno Setup.
; It unpacks the package (dist\harfi-windows) into a temporary folder and runs "Install Harfi.exe --install" from there;
; install.ps1 then installs for this user into %LOCALAPPDATA%\Harfi, as from the zip. The temporary folder is removed
; when it ends, and Harfi-Setup.exe itself installs nothing and has no uninstaller (Harfi's own is in Installed apps).
;   iscc /DVersion=0.3.0 Apps\HarfiWindows\setup.iss   ->   dist\Harfi-Setup.exe
#ifndef Version
  #define Version "0.0.0"
#endif

[Setup]
AppName=Harfi
AppVersion={#Version}
AppPublisher=Harfi (open source)
VersionInfoVersion={#Version}
PrivilegesRequired=lowest
CreateAppDir=no
Uninstallable=no
DisableWelcomePage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
SetupIconFile=src\settings\harfi.ico
OutputDir=..\..\dist
OutputBaseFilename=Harfi-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\..\dist\harfi-windows\*"; DestDir: "{tmp}\harfi"; Flags: recursesubdirs

[Run]
Filename: "{tmp}\harfi\Install Harfi.exe"; Parameters: "--install"; Flags: waituntilterminated
