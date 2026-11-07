# Shows which Harfi build is installed, and which running apps use it. An app keeps the build it loaded until it is
# restarted (install.ps1 moves locked files aside), so an app on an older build needs a restart to get the latest.
#   powershell -ExecutionPolicy Bypass -File status.ps1
$ErrorActionPreference = "Stop"
$dll = Join-Path $env:LOCALAPPDATA "Harfi\HarfiTIP.dll"
if (-not (Test-Path $dll)) { Write-Host "Harfi is not installed."; exit 1 }

Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class HarfiStamp {
    [DllImport("kernel32", SetLastError = true)] static extern IntPtr OpenProcess(int access, bool inherit, int id);
    [DllImport("kernel32", SetLastError = true)] static extern bool ReadProcessMemory(IntPtr process, IntPtr at, byte[] into, int size, out IntPtr read);
    [DllImport("kernel32")] static extern bool CloseHandle(IntPtr handle);
    // The linker's build stamp (TimeDateStamp in the PE header) of the module loaded at `base` in process `id`.
    public static uint Loaded(int id, IntPtr baseAddress) {
        IntPtr process = OpenProcess(0x0010 | 0x0400, false, id);  // VM_READ | QUERY_INFORMATION
        if (process == IntPtr.Zero) return 0;
        try {
            byte[] header = new byte[0x400];
            IntPtr read;
            if (!ReadProcessMemory(process, baseAddress, header, header.Length, out read)) return 0;
            int pe = BitConverter.ToInt32(header, 0x3C);
            return pe > 0 && pe + 12 <= header.Length ? BitConverter.ToUInt32(header, pe + 8) : 0;
        } finally { CloseHandle(process); }
    }
    // The same stamp from a file on disk.
    public static uint File(string path) {
        byte[] header = new byte[0x400];
        using (var file = System.IO.File.OpenRead(path)) file.Read(header, 0, header.Length);
        return BitConverter.ToUInt32(header, BitConverter.ToInt32(header, 0x3C) + 8);
    }
}
"@

function Built([uint32]$stamp) {
    if ($stamp -eq 0) { return "unknown" }
    return [DateTimeOffset]::FromUnixTimeSeconds($stamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
}

$installed = [HarfiStamp]::File($dll)
Write-Host "Installed build: $(Built $installed)   ($dll)"

$apps = foreach ($process in Get-Process) {
    $module = try { $process.Modules | Where-Object { $_.ModuleName -eq "HarfiTIP.dll" } | Select-Object -First 1 } catch { $null }
    if (-not $module) { continue }
    $stamp = [HarfiStamp]::Loaded($process.Id, $module.BaseAddress)
    [pscustomobject]@{
        App   = $process.ProcessName
        Id    = $process.Id
        Build = Built $stamp
        State = if ($stamp -eq $installed) { "latest" } elseif ($stamp -eq 0) { "cannot tell" } else { "OLDER: restart this app" }
    }
}
if ($apps) { $apps | Sort-Object App | Format-Table -AutoSize | Out-String | Write-Host }
else { Write-Host "No running app has Harfi loaded yet (it loads when you switch to it in an app)." }

# The engine (harfi-engine.exe): the conversion model runs there. The keyboard starts it when it is first used, and it
# quits after half an hour without a request.
$pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", "harfi-engine-$($env:USERNAME -replace '[^\w-]', '')", "InOut")
try {
    $pipe.Connect(1000)
    $writer = New-Object System.IO.StreamWriter($pipe)
    $writer.AutoFlush = $true
    $writer.Write("status`n")
    $status = (New-Object System.IO.StreamReader($pipe)).ReadLine() | ConvertFrom-Json
    $model = switch ($status.state) {
        "ready" { "model $($status.model) ready" }
        "unavailable" { "model unavailable: $($status.reason) (the rules convert)" }
        default { "model switched off (the rules convert)" }
    }
    if ($status.loading) { $model = "still loading the model (the rules convert meanwhile)" }
    Write-Host "Engine: running, $model."
} catch {
    Write-Host "Engine: not running (it starts when you next type with Harfi)."
} finally {
    $pipe.Dispose()
}
