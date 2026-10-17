param([string]$OutDir, [string]$PreviewDir)
# White, tintable UI textures for the window (32-bit TGA, power-of-two):
#   powershell -File tools\MakeUITextures.ps1 -OutDir media\ui [-PreviewDir <png folder>]
# Shapes follow the design mockup (24-unit role glyphs, 16-unit lust / brez).
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $OutDir | Out-Null
$W = [System.Drawing.Color]::White

function New-Canvas($size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)
    return @($bmp, $g)
}

function Save-Tga($bmp, $name) {
    $s = $bmp.Width
    if ($PreviewDir) { $bmp.Save((Join-Path $PreviewDir "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png) }
    $data = $bmp.LockBits((New-Object System.Drawing.Rectangle(0, 0, $s, $s)), 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $s)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bmp.UnlockBits($data)
    # White everywhere, coverage in alpha: tinting with vertex colors stays clean.
    for ($i = 0; $i -lt $bytes.Length; $i += 4) { $bytes[$i] = 255; $bytes[$i+1] = 255; $bytes[$i+2] = 255 }
    $h = New-Object byte[] 18
    $h[2] = 2; $h[12] = $s; $h[14] = $s; $h[16] = 32; $h[17] = 0x28
    $fs = [System.IO.File]::Create((Join-Path $OutDir "$name.tga"))
    $fs.Write($h, 0, 18); $fs.Write($bytes, 0, $bytes.Length); $fs.Close()
    $bmp.Dispose()
}

function RoundRectPath($x, $y, $w, $h, $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}

# Rounded rectangle, radius 6, sliced with margins 8 in game.
$c = New-Canvas 32; $c[1].FillPath((New-Object System.Drawing.SolidBrush($W)), (RoundRectPath 0 0 32 32 6)); $c[1].Dispose(); Save-Tga $c[0] "round-fill"
$c = New-Canvas 32; $c[1].DrawPath((New-Object System.Drawing.Pen($W, 1)), (RoundRectPath 0.5 0.5 31 31 5.5)); $c[1].Dispose(); Save-Tga $c[0] "round-border"

# Corner cap: what lies outside a radius-6 corner (covers square art corners).
$c = New-Canvas 8
$p = New-Object System.Drawing.Drawing2D.GraphicsPath
$p.AddRectangle((New-Object System.Drawing.RectangleF(0, 0, 6, 6)))
$hole = New-Object System.Drawing.Drawing2D.GraphicsPath
$hole.AddEllipse(0, 0, 12, 12)
$region = New-Object System.Drawing.Region($p); $region.Exclude($hole)
$c[1].FillRegion((New-Object System.Drawing.SolidBrush($W)), $region); $c[1].Dispose(); Save-Tga $c[0] "corner-cap"

# Circles and rings (64 px; shown at 24-30 px).
$c = New-Canvas 64; $c[1].FillEllipse((New-Object System.Drawing.SolidBrush($W)), 1, 1, 62, 62); $c[1].Dispose(); Save-Tga $c[0] "circle"
$c = New-Canvas 64; $c[1].DrawEllipse((New-Object System.Drawing.Pen($W, 3.5)), 2, 2, 60, 60); $c[1].Dispose(); Save-Tga $c[0] "ring"
$c = New-Canvas 64
$pen = New-Object System.Drawing.Pen($W, 3.5); $pen.DashStyle = 'Custom'; $pen.DashPattern = @([single]2.2, [single]1.6)
$c[1].DrawEllipse($pen, 2, 2, 60, 60); $c[1].Dispose(); Save-Tga $c[0] "ring-dashed"

function P($x, $y, $k) { New-Object System.Drawing.PointF(($x * $k), ($y * $k)) }

# Role glyphs, 24-unit geometry scaled to 64.
$k = 64 / 24.0
$c = New-Canvas 64
$p = New-Object System.Drawing.Drawing2D.GraphicsPath
$p.AddLine((P 12 5.4 $k), (P 17.2 7.3 $k)); $p.AddLine((P 17.2 7.3 $k), (P 17.2 10.9 $k))
$p.AddBezier((P 17.2 10.9 $k), (P 17.2 14.2 $k), (P 15 16.7 $k), (P 12 18 $k))
$p.AddBezier((P 12 18 $k), (P 9 16.7 $k), (P 6.8 14.2 $k), (P 6.8 10.9 $k))
$p.AddLine((P 6.8 10.9 $k), (P 6.8 7.3 $k)); $p.CloseFigure()
$c[1].FillPath((New-Object System.Drawing.SolidBrush($W)), $p); $c[1].Dispose(); Save-Tga $c[0] "glyph-tank"

$c = New-Canvas 64
$b = New-Object System.Drawing.SolidBrush($W)
$c[1].FillRectangle($b, 10.3 * $k, 5.6 * $k, 3.4 * $k, 12.8 * $k); $c[1].FillRectangle($b, 5.6 * $k, 10.3 * $k, 12.8 * $k, 3.4 * $k)
$c[1].Dispose(); Save-Tga $c[0] "glyph-healer"

$c = New-Canvas 64
$b = New-Object System.Drawing.SolidBrush($W)
$c[1].FillPolygon($b, [System.Drawing.PointF[]]@((P 17.9 5 $k), (P 19 6.1 $k), (P 11.6 14.1 $k), (P 9.8 12.3 $k)))
$c[1].FillPolygon($b, [System.Drawing.PointF[]]@((P 8.1 12.1 $k), (P 11.9 15.9 $k), (P 10.8 17 $k), (P 7 13.2 $k)))
$c[1].FillPolygon($b, [System.Drawing.PointF[]]@((P 8.3 15.3 $k), (P 9.5 16.5 $k), (P 6.9 19.1 $k), (P 5.7 17.9 $k)))
$c[1].Dispose(); Save-Tga $c[0] "glyph-dps"

# Lust (bolt) and battle res (heart), 16-unit geometry scaled to 64.
$k = 4
$c = New-Canvas 64
$c[1].FillPolygon((New-Object System.Drawing.SolidBrush($W)), [System.Drawing.PointF[]]@((P 9.4 1.2 $k), (P 3.2 9.1 $k), (P 7.7 9.1 $k), (P 6.6 14.8 $k), (P 12.8 6.9 $k), (P 8.3 6.9 $k)))
$c[1].Dispose(); Save-Tga $c[0] "glyph-lust"

$c = New-Canvas 64
$b = New-Object System.Drawing.SolidBrush($W)
$c[1].FillEllipse($b, 2.3 * $k, 3.3 * $k, 6.0 * $k, 6.0 * $k)
$c[1].FillEllipse($b, 7.7 * $k, 3.3 * $k, 6.0 * $k, 6.0 * $k)
$c[1].FillPolygon($b, [System.Drawing.PointF[]]@((P 2.55 7.4 $k), (P 8 13.9 $k), (P 13.45 7.4 $k), (P 8 5.5 $k)))
$c[1].Dispose(); Save-Tga $c[0] "glyph-brez"

"ok"
