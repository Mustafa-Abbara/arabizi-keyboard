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
