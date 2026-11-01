# Installs (or removes) the Windows keyboard from this folder for the current user (ADR 0032, test builds).
#   Right-click > Run with PowerShell, or:  powershell -ExecutionPolicy Bypass -File install.ps1 [-Uninstall]
# Copies the files to %LOCALAPPDATA%\Harfi, registers HarfiTIP.dll, and asks for administrator rights only if
# Windows needs them to register the keyboard profile.
param([switch]$Uninstall)
$ErrorActionPreference = "Stop"
$target = Join-Path $env:LOCALAPPDATA "Harfi"
$dll = Join-Path $target "HarfiTIP.dll"

function Register([string]$arguments) {
    $process = Start-Process regsvr32.exe -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Host "Registering needs administrator rights on this PC; Windows will ask once."
        $process = Start-Process regsvr32.exe -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    }
    return $process.ExitCode -eq 0
}

if ($Uninstall) {
    if (Test-Path $dll) { [void](Register "/s /u `"$dll`"") }
    Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
    Write-Host "Harfi removed. If it still shows as a keyboard, remove it in Settings > Language & region."
    exit 0
}

New-Item -ItemType Directory -Force $target | Out-Null
Copy-Item -Recurse -Force (Join-Path $PSScriptRoot "*") $target
if (-not (Register "/s `"$dll`"")) { Write-Host "Registration failed."; exit 1 }
Write-Host @"
Harfi is installed in $target.
Turn it on once: Settings > Time & language > Language & region > Arabic (Lebanon) > Language options >
Add a keyboard > Harfi. (Add the Arabic (Lebanon) language first if it is not listed.)
Then switch with Win+Space, open Notepad, type: shu 3am ta3mel   and press Enter.
"@
