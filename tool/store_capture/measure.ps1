# Layout QA for the store assets: reports, per slide, where the headline block
# ends vs. where the front phone starts, headline line count, and whether every
# image loaded. Flags overlaps (copyBottom > frontPhoneTop - 24).
$root = Resolve-Path "$PSScriptRoot\..\.."
$html = Join-Path $root 'play-store-assets\store-2026\classtrack-play-assets.html'
$uri = ([Uri]$html).AbsoluteUri
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$profileDir = Join-Path $env:TEMP 'ct-measure-profile'
$dom = Join-Path $env:TEMP 'ct-measure.html'
foreach ($k in '1','2','3','4','5','6','7','8','fg') {
  $dom = Join-Path $env:TEMP "ct-measure-$k.html"
  $size = if ($k -eq 'fg') { '1024,500' } else { '1080,1920' }
  # Chrome only writes --dump-dom to a real stdout handle, so go through cmd.
  cmd /c "`"$chrome`" --headless=new --disable-gpu --user-data-dir=`"$profileDir`" --allow-file-access-from-files --virtual-time-budget=4000 --window-size=$size --dump-dom `"$uri`?slide=$k&measure=1`" > `"$dom`" 2>nul"
  $m = [regex]::Match((Get-Content $dom -Raw), '<pre id="measure">(.*?)</pre>').Groups[1].Value
  if (-not $m) { "slide $k : NO MEASUREMENT"; continue }
  $j = $m.Replace('&quot;', '"') | ConvertFrom-Json
  $flag = if ($k -ne 'fg' -and $j.copyBottom -gt ($j.frontPhoneTop - 24)) { '  <-- OVERLAP' } else { '' }
  $img = if ($j.imagesOk) { 'ok' } else { 'BROKEN' }
  "slide {0,-2}: h1 {1} lines | copy ends {2} | phone {3}-{4} | images {5} ({6}){7}" -f $k, $j.h1Lines, $j.copyBottom, $j.frontPhoneTop, $j.frontPhoneBottom, $img, $j.images, $flag
  Start-Sleep -Milliseconds 500
  Remove-Item $dom -ErrorAction SilentlyContinue
}
Remove-Item -Recurse -Force $profileDir -ErrorAction SilentlyContinue
