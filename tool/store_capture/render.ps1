# Renders the Play Store assets from classtrack-play-assets.html with headless
# Chrome. Run from the project root after capturing real screens:
#   flutter test tool/store_capture/capture_test.dart --update-goldens
#   powershell -ExecutionPolicy Bypass -File tool/store_capture/render.ps1
$ErrorActionPreference = 'Continue'
$root = Resolve-Path "$PSScriptRoot\..\.."
$html = Join-Path $root 'play-store-assets\store-2026\classtrack-play-assets.html'
$out = Join-Path $root 'play-store-assets\store-2026\final'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$chrome = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw 'Chrome/Edge not found.' }

$names = @{
  '1' = '01-hero-whole-student-life'; '2' = '02-attendance'; '3' = '03-ai-planner';
  '4' = '04-schedule'; '5' = '05-tasks-exams'; '6' = '06-grades';
  '7' = '07-opportunities'; '8' = '08-ai-assistant'; 'fg' = 'feature-graphic-1024x500'
}
$uri = ([Uri]$html).AbsoluteUri
$profileDir = Join-Path $env:TEMP 'ct-render-profile'
foreach ($k in '1','2','3','4','5','6','7','8','fg') {
  $size = if ($k -eq 'fg') { '1024,500' } else { '1080,1920' }
  $file = Join-Path $out "$($names[$k]).png"
  & $chrome --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 `
    --user-data-dir="$profileDir" --allow-file-access-from-files `
    --virtual-time-budget=4000 --window-size=$size --screenshot="$file" "$uri`?slide=$k" 2>&1 | Out-Null
  if (-not (Test-Path $file)) { throw "Render failed for slide $k" }
  Start-Sleep -Milliseconds 300
  # Google Play requires 24-bit PNG/JPEG (no alpha): flatten onto white.
  Add-Type -AssemblyName System.Drawing
  $src = [System.Drawing.Image]::FromFile($file)
  $flat = New-Object System.Drawing.Bitmap $src.Width, $src.Height, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($flat); $g.Clear([System.Drawing.Color]::White); $g.DrawImage($src, 0, 0, $src.Width, $src.Height); $g.Dispose(); $src.Dispose()
  $flat.Save("$file.tmp", [System.Drawing.Imaging.ImageFormat]::Png); $flat.Dispose()
  Move-Item -Force "$file.tmp" $file
  Write-Host $file
}
Remove-Item -Recurse -Force $profileDir -ErrorAction SilentlyContinue
