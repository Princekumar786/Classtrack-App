param([Parameter(Mandatory)][string[]]$Paths, [int]$Width = 360)
# Writes small JPEG previews next to $env:TEMP\previews for quick visual QA.
Add-Type -AssemblyName System.Drawing
$out = Join-Path $env:TEMP 'previews'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]70)
foreach ($p in $Paths) {
  $src = [System.Drawing.Image]::FromFile((Resolve-Path $p))
  $h = [int]($src.Height * $Width / $src.Width)
  $dst = New-Object System.Drawing.Bitmap $Width, $h
  $g = [System.Drawing.Graphics]::FromImage($dst)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($src, 0, 0, $Width, $h)
  $name = [IO.Path]::GetFileNameWithoutExtension($p) + '.jpg'
  $dst.Save((Join-Path $out $name), $codec, $ep)
  $g.Dispose(); $dst.Dispose(); $src.Dispose()
  Join-Path $out $name
}
