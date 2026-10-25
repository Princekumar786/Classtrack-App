# Renders the v2 (pastel) Play Store assets from classtrack-play-assets-v2.html
# with headless Chrome. Run from the project root after capturing real screens:
#   flutter test tool/store_capture/capture_test.dart --update-goldens
#   powershell -ExecutionPolicy Bypass -File tool/store_capture/render_v2.ps1
# Output: play-store-assets/store-2026-v2/final/{phone,wide}/*.png + feature graphic.
$ErrorActionPreference = 'Continue'  # Chrome logs to stderr; failures are checked explicitly.
$root = Resolve-Path "$PSScriptRoot\..\.."
$html = Join-Path $root 'play-store-assets\store-2026-v2\classtrack-play-assets-v2.html'
$out = Join-Path $root 'play-store-assets\store-2026-v2\final'
foreach ($d in 'phone', 'wide') { New-Item -ItemType Directory -Force -Path (Join-Path $out $d) | Out-Null }

$chrome = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw 'Chrome/Edge not found.' }
Add-Type -AssemblyName System.Drawing

$names = @{
  '1' = '01-attendance'; '2' = '02-ai-timetable-import'; '3' = '03-tasks'; '4' = '04-exams';
  '5' = '05-ai-study-planner'; '6' = '06-grades-gpa'; '7' = '07-ai-assistant'; '8' = '08-opportunities'
}
$uri = ([Uri]$html).AbsoluteUri
$profileDir = Join-Path $env:TEMP 'ct-render-v2-profile'

function Render($query, $size, $file) {
  & $chrome --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 `
    --user-data-dir="$profileDir" --allow-file-access-from-files `
    --virtual-time-budget=5000 --window-size=$size --screenshot="$file" "$uri`?$query" 2>&1 | Out-Null
  if (-not (Test-Path $file)) { throw "Render failed: $query" }
  # Google Play wants 24-bit PNG (no alpha): flatten onto white.
  $src = [System.Drawing.Image]::FromFile($file)
  $flat = New-Object System.Drawing.Bitmap $src.Width, $src.Height, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($flat); $g.Clear([System.Drawing.Color]::White)
  $g.DrawImage($src, 0, 0, $src.Width, $src.Height); $g.Dispose(); $src.Dispose()
  $flat.Save("$file.tmp", [System.Drawing.Imaging.ImageFormat]::Png); $flat.Dispose()
  Move-Item -Force "$file.tmp" $file
  Write-Host $file
}

foreach ($k in '1','2','3','4','5','6','7','8') {
  Render "fmt=phone&slide=$k" '1080,1920' (Join-Path $out "phone\$($names[$k]).png")
  Render "fmt=wide&slide=$k" '1920,1080' (Join-Path $out "wide\$($names[$k]).png")
}
Render 'fmt=fg' '1024,500' (Join-Path $out 'feature-graphic-1024x500.png')
Remove-Item -Recurse -Force $profileDir -ErrorAction SilentlyContinue
