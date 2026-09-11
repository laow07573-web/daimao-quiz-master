# 从 assets/app_logo.png 生成 windows/runner/resources/app_icon.ico
# 纯 System.Drawing 实现：小尺寸用 BMP DIB、256 用 PNG 压缩条目
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$src = 'd:\dev\flashcard_app\assets\app_logo.png'
$dst = 'd:\dev\flashcard_app\windows\runner\resources\app_icon.ico'

function Get-BmpEntry([System.Drawing.Bitmap]$bmp, [int]$size) {
    $resized = New-Object System.Drawing.Bitmap($bmp, $size, $size)
    $px = New-Object 'byte[]' ($size * $size * 4)
    $i = 0
    for ($y = $size - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $size; $x++) {
            $c = $resized.GetPixel($x, $y)
            $px[$i++] = $c.B; $px[$i++] = $c.G; $px[$i++] = $c.R; $px[$i++] = $c.A
        }
    }
    # AND mask：每行按 32 位对齐
    $rowBytes = [int]([Math]::Ceiling($size / 32.0)) * 4
    $mask = New-Object 'byte[]' ($rowBytes * $size)
    $header = New-Object 'byte[]' 40
    [BitConverter]::GetBytes([uint32]40).CopyTo($header, 0)
    [BitConverter]::GetBytes([int32]$size).CopyTo($header, 4)
    [BitConverter]::GetBytes([int32]($size * 2)).CopyTo($header, 8)
    [BitConverter]::GetBytes([uint16]1).CopyTo($header, 12)
    [BitConverter]::GetBytes([uint16]32).CopyTo($header, 14)
    [BitConverter]::GetBytes([uint32]($px.Length + $mask.Length)).CopyTo($header, 20)
    $resized.Dispose()
    return $header + $px + $mask
}

function Get-PngEntry([System.Drawing.Bitmap]$bmp, [int]$size) {
    $resized = New-Object System.Drawing.Bitmap($bmp, $size, $size)
    $ms = New-Object System.IO.MemoryStream
    $resized.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $resized.Dispose()
    return $ms.ToArray()
}

$logo = [System.Drawing.Bitmap]::FromFile($src)
$sizes = 16, 24, 32, 48, 64, 128, 256
$entries = @()
foreach ($s in $sizes) {
    if ($s -ge 256) { $entries += ,@(Get-PngEntry $logo $s) } else { $entries += ,@(Get-BmpEntry $logo $s) }
}
$logo.Dispose()

$fs = [System.IO.File]::Create($dst)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([uint16]0)          # reserved
$bw.Write([uint16]1)          # type: icon
$bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($k = 0; $k -lt $sizes.Count; $k++) {
    $s = $sizes[$k]; $data = $entries[$k]
    $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))
    $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))
    $bw.Write([byte]0)        # colors
    $bw.Write([byte]0)        # reserved
    $bw.Write([uint16]1)      # planes
    $bw.Write([uint16]32)     # bpp
    $bw.Write([uint32]$data.Length)
    $bw.Write([uint32]$offset)
    $offset += $data.Length
}
foreach ($data in $entries) { $bw.Write([byte[]]$data) }
$bw.Close(); $fs.Close()
Write-Output "OK: $dst ($((Get-Item $dst).Length) bytes, $($sizes.Count) sizes)"
