# Installs (or removes) the Windows keyboard from this folder for the current user (ADR 0032, test builds).
#   Right-click > Run with PowerShell, or:  powershell -ExecutionPolicy Bypass -File install.ps1 [-Uninstall]
# Copies the files to %LOCALAPPDATA%\Harfi, registers HarfiTIP.dll, and asks for administrator rights only if
# Windows needs them to register the keyboard profile. The conversion model (808 MB) comes with this folder when it
# holds models\; otherwise it is downloaded once from the model release, in parts, each checked, as on the Mac.
param([switch]$Uninstall)
$ErrorActionPreference = "Stop"
$target = Join-Path $env:LOCALAPPDATA "Harfi"
$dll = Join-Path $target "HarfiTIP.dll"
$modelRelease = "https://github.com/Mustafa-Abbara/arabizi-keyboard/releases/download/model-v3"
$modelParts = "Llama-3.2-1B-Harfi-v3-Q4_K_M.gguf"  # the release's part names: .part01 ... and .parts.sha256

# The engine keeps its files open; the keyboard starts it again when it is next needed.
function Stop-Engine {
    Get-Process harfi-engine -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($target, [StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

# The model config\engine.json switches on, with its file, size and SHA-256 from config\models.json.
function Get-Model([string]$folder) {
    $engine = Get-Content -Raw (Join-Path $folder "config\engine.json") | ConvertFrom-Json
    $models = Get-Content -Raw (Join-Path $folder "config\models.json") | ConvertFrom-Json
    return $models.models | Where-Object { $_.id -eq $engine.model } | Select-Object -First 1
}

# Downloads the model's parts (resuming a broken download), checks each against the release's list, joins them and
# checks the whole file.
function Get-ModelFile($model, [string]$file) {
    $parts = Join-Path $target "models\download"
    New-Item -ItemType Directory -Force $parts | Out-Null
    Write-Host "Downloading the conversion model ($([math]::Round($model.size / 1MB)) MB, once)..."
    $list = Join-Path $parts "$modelParts.parts.sha256"
    curl.exe -fsSL -o $list "$modelRelease/$modelParts.parts.sha256"
    if ($LASTEXITCODE -ne 0) { throw "The model list could not be downloaded." }
    $names = @()
    foreach ($line in Get-Content $list) {
        if ($line -notmatch '^([0-9a-f]{64})\s+\*?(\S+)$') { continue }
        $hash, $name = $Matches[1], $Matches[2]
        $part = Join-Path $parts $name
        curl.exe -fL -C - --retry 5 -o $part "$modelRelease/$name"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 33) { throw "Downloading $name failed. Run install.ps1 again to resume." }
        if ((Get-FileHash -Algorithm SHA256 $part).Hash.ToLower() -ne $hash) {
            Remove-Item $part
            throw "$name is damaged. Run install.ps1 again."
        }
        $names += $part
    }
    $joined = [IO.File]::Create($file)
    try { foreach ($part in $names) { $in = [IO.File]::OpenRead($part); try { $in.CopyTo($joined) } finally { $in.Dispose() } } }
    finally { $joined.Dispose() }
    if ((Get-FileHash -Algorithm SHA256 $file).Hash.ToLower() -ne $model.sha256) {
        Remove-Item $file
        throw "The joined model does not match its SHA-256. Run install.ps1 again."
    }
    Remove-Item -Recurse -Force $parts
}

function Register([string]$arguments) {
    $process = Start-Process regsvr32.exe -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Host "Registering needs administrator rights on this PC; Windows will ask once."
        $process = Start-Process regsvr32.exe -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    }
    return $process.ExitCode -eq 0
}

if ($Uninstall) {
    Stop-Engine
    if (Test-Path $dll) { [void](Register "/s /u `"$dll`"") }
    Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
    Write-Host "Harfi removed. If it still shows as a keyboard, remove it in Settings > Language & region."
    exit 0
}

$source = (Resolve-Path $PSScriptRoot).Path.TrimEnd("\")
New-Item -ItemType Directory -Force $target | Out-Null
Stop-Engine
if ($source -ne (Resolve-Path $target).Path.TrimEnd("\")) {
    # An app that still has the old keyboard loaded keeps its files locked: they cannot be replaced, but they can be
    # renamed. Move those aside (and remove the ones earlier installs moved aside, once nothing uses them any more).
    Get-ChildItem $target -Recurse -File -Filter "*.old" | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem $source -Recurse -File | Where-Object { $_.Extension -notin ".log", ".old" } | ForEach-Object {
        $existing = Join-Path $target $_.FullName.Substring($source.Length + 1)
        if ($_.Extension -eq ".gguf" -and (Test-Path $existing) -and (Get-Item $existing).Length -eq $_.Length) {
            return  # the same model is already there: 808 MB not copied again
        }
        if (Test-Path $existing) {
            try { Remove-Item -Force $existing }
            catch { Rename-Item $existing "$(Split-Path $existing -Leaf).$([guid]::NewGuid().ToString('N')).old" }
        }
        New-Item -ItemType Directory -Force (Split-Path $existing) | Out-Null
        Copy-Item -Force $_.FullName $existing
    }
}
$model = Get-Model $target
if ($model) {
    $modelFile = Join-Path $target "models\$($model.file)"
    if (-not ((Test-Path $modelFile) -and (Get-Item $modelFile).Length -eq $model.size)) {
        New-Item -ItemType Directory -Force (Split-Path $modelFile) | Out-Null
        Get-ModelFile $model $modelFile
    }
}
# Run from inside a packaged app (a terminal in the Claude or another Store app), Windows quietly puts new AppData
# folders in that app's private storage, where no other app can load the keyboard from.
$private = Get-ChildItem (Join-Path $env:LOCALAPPDATA "Packages\*\LocalCache\Local\Harfi\HarfiTIP.dll") -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) }
if ($private) {
    Write-Host "This window belongs to a packaged app, so the files went to its private storage ($($private[0].DirectoryName))."
    Write-Host "Other apps cannot use them there. Run install.ps1 again from a normal PowerShell window (Start > PowerShell)."
    exit 1
}
# Store apps and the Start menu search box run in an app container: let them read the keyboard's files too.
icacls $target /grant "*S-1-15-2-1:(OI)(CI)(RX)" /T /Q | Out-Null
if (-not (Register "/s `"$dll`"")) { Write-Host "Registration failed."; exit 1 }
Write-Host @"
Harfi is installed in $target.
Turn it on once: Settings > Time & language > Language & region > Arabic (Lebanon) > Language options >
Add a keyboard > Harfi. (Add the Arabic (Lebanon) language first if it is not listed.)
Then switch with Win+Space, open Notepad, type: shu 3am ta3mel   and press Enter.
"@
