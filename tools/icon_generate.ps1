# Launcher icon generator: crop the Canva logo content tight, scale to 96%
# of canvas width, center on white background, write all 5 mipmap densities.
# NOTE: keep this file pure-ASCII; PS 5.1 misparses UTF-8 comments without BOM.
Add-Type -AssemblyName System.Drawing

$srcPath = 'D:\Download\Canva - download (2).png'
$targets = @(
  @{ Dir = 'android\app\src\main\res\mipmap-mdpi';    Size = 48 },
  @{ Dir = 'android\app\src\main\res\mipmap-hdpi';    Size = 72 },
  @{ Dir = 'android\app\src\main\res\mipmap-xhdpi';   Size = 96 },
  @{ Dir = 'android\app\src\main\res\mipmap-xxhdpi';  Size = 144 },
  @{ Dir = 'android\app\src\main\res\mipmap-xxxhdpi'; Size = 192 }
)

$img = [System.Drawing.Image]::FromFile($srcPath)
$src = New-Object System.Drawing.Bitmap($img)
$W = $src.Width
$H = $src.Height

# exact content bbox (non-white pixels, step 1)
$minX = $W; $minY = $H; $maxX = -1; $maxY = -1
for ($y = 0; $y -lt $H; $y += 1) {
  for ($x = 0; $x -lt $W; $x += 1) {
    $p = $src.GetPixel($x, $y)
    if ($p.R -lt 240 -or $p.G -lt 240 -or $p.B -lt 240) {
      if ($x -lt $minX) { $minX = $x }
      if ($x -gt $maxX) { $maxX = $x }
      if ($y -lt $minY) { $minY = $y }
      if ($y -gt $maxY) { $maxY = $y }
    }
  }
}
$bw = $maxX - $minX + 1
$bh = $maxY - $minY + 1
Write-Output ("content bbox: x[{0}..{1}] y[{2}..{3}]  {4}x{5}" -f $minX, $maxX, $minY, $maxY, $bw, $bh)

foreach ($t in $targets) {
  $size = $t.Size
  $canvas = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($canvas)
  $g.Clear([System.Drawing.Color]::White)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

  $scale = ($size * 0.96) / $bw
  $dw = [int][Math]::Round($bw * $scale)
  $dh = [int][Math]::Round($bh * $scale)
  $dx = [int](($size - $dw) / 2)
  $dy = [int](($size - $dh) / 2)

  $srcRect = New-Object System.Drawing.Rectangle($minX, $minY, $bw, $bh)
  $dstRect = New-Object System.Drawing.Rectangle($dx, $dy, $dw, $dh)
  $g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()

  $out = Join-Path $t.Dir 'ic_launcher.png'
  $canvas.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $canvas.Dispose()
  Write-Output ("wrote {0}  ({1}x{1}, content {2}x{3})" -f $out, $size, $dw, $dh)
}
$src.Dispose()
$img.Dispose()
