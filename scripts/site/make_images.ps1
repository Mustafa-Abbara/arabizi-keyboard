# Renders the website's images from their sources with Microsoft Edge (headless), on Windows:
#   site/og.png                the link preview (1200x630), from scripts/site/og.html
#   site/icon-32.png           the tab icon for browsers without SVG icons, from site/icon.svg
#   site/apple-touch-icon.png  the home-screen icon (180x180, square: the phone rounds it), from icon-square.svg
# Run again after changing site/icon.svg or og.html:  powershell -File scripts/site/make_images.ps1
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "../..")
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$profile = Join-Path ([IO.Path]::GetTempPath()) "harfi-site-images"
function Shoot($page, $out, $width, $height, [switch]$Clear) {
    $url = "file:///" + (Join-Path $root $page).Replace('\', '/').Replace(' ', '%20')
    $arguments = @("--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
        "--virtual-time-budget=3000", "--window-size=$width,$height", "--user-data-dir=`"$profile`"",
        "--screenshot=`"$(Join-Path $root $out)`"", $url)
    if ($Clear) { $arguments += "--default-background-color=00000000" }
    Start-Process $edge -ArgumentList $arguments -Wait
    if (-not (Test-Path (Join-Path $root $out))) { throw "Edge did not write $out" }
}
# An icon at an exact size: a page that only holds the SVG.
function Icon($svg, $out, $size) {
    $page = Join-Path $profile "icon.html"
    New-Item -ItemType Directory -Force $profile | Out-Null
    $source = "file:///" + (Join-Path $root $svg).Replace('\', '/').Replace(' ', '%20')
    Set-Content -Encoding utf8 $page "<!doctype html><style>html,body{margin:0;background:transparent}</style><img src=""$source"" width=""$size"" height=""$size"" style=""display:block"">"
    $url = "file:///" + $page.Replace('\', '/').Replace(' ', '%20')
    Start-Process $edge -ArgumentList @("--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
        "--virtual-time-budget=2000", "--window-size=$size,$size", "--user-data-dir=`"$profile`"", "--default-background-color=00000000",
        "--screenshot=`"$(Join-Path $root $out)`"", $url) -Wait
}
Shoot "scripts/site/og.html" "site/og.png" 1200 630
Icon "site/icon.svg" "site/icon-32.png" 32
Icon "scripts/site/icon-square.svg" "site/apple-touch-icon.png" 180
Get-Item (Join-Path $root "site/og.png"), (Join-Path $root "site/icon-32.png"), (Join-Path $root "site/apple-touch-icon.png") | Format-Table Name, Length

# The Windows programs' icon (the Harfi window and the installer): Apps/HarfiWindows/src/settings/harfi.ico, from the
# same site/icon.svg. Drawn once at 256 px, scaled down to the sizes Windows asks for, each stored as a PNG.
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force (Join-Path $root "build") | Out-Null
$large = Join-Path $root "build/icon-256.png"  # build/ is not committed
Icon "site/icon.svg" "build/icon-256.png" 256
$source = [Drawing.Image]::FromFile($large)
$images = foreach ($size in 16, 20, 24, 32, 40, 48, 64, 256) {
    $bitmap = New-Object Drawing.Bitmap $size, $size, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($source, 0, 0, $size, $size)
    $graphics.Dispose()
    $stream = New-Object IO.MemoryStream
    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    [pscustomobject]@{ Size = $size; Bytes = $stream.ToArray() }
}
$source.Dispose()
$ico = New-Object IO.MemoryStream
$writer = New-Object IO.BinaryWriter $ico
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($image in $images) {
    $writer.Write([byte]($image.Size % 256)); $writer.Write([byte]($image.Size % 256))  # 0 means 256
    $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$image.Bytes.Length); $writer.Write([uint32]$offset)
    $offset += $image.Bytes.Length
}
foreach ($image in $images) { $writer.Write($image.Bytes) }
[IO.File]::WriteAllBytes((Join-Path $root "Apps/HarfiWindows/src/settings/harfi.ico"), $ico.ToArray())
Get-Item (Join-Path $root "Apps/HarfiWindows/src/settings/harfi.ico") | Format-Table Name, Length
