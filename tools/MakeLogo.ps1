param([string]$OutDir, [int]$Size = 128, [string]$Name = "logo-qlens", [switch]$NoTile)
# Renders the Q-Lens logo as 32-bit TGA (WoW texture) and PNG:
#   powershell -File tools\MakeLogo.ps1 -OutDir media                               (tile: CurseForge icon)
#   powershell -File tools\MakeLogo.ps1 -OutDir media -Name logo-qlens-mark -NoTile (mark: in game)
# Geometry follows the 256-unit SVG of the design mockup.
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)
$k = $Size / 256.0
$g.ScaleTransform($k, $k)

function C($hex, $a = 255) { [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($hex.Substring(0,2),16), [Convert]::ToInt32($hex.Substring(2,2),16), [Convert]::ToInt32($hex.Substring(4,2),16)) }

# Rounded tile, navy radial-ish gradient.
$tile = New-Object System.Drawing.Drawing2D.GraphicsPath
$r = 52; $x = 8; $y = 8; $w = 240; $h = 240
$tile.AddArc($x, $y, $r*2, $r*2, 180, 90); $tile.AddArc($x+$w-$r*2, $y, $r*2, $r*2, 270, 90)
$tile.AddArc($x+$w-$r*2, $y+$h-$r*2, $r*2, $r*2, 0, 90); $tile.AddArc($x, $y+$h-$r*2, $r*2, $r*2, 90, 90)
$tile.CloseFigure()
$bgBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($tile)
$bgBrush.CenterPoint = New-Object System.Drawing.PointF(80, 60)
$bgBrush.CenterColor = C "1D2D4C"
$bgBrush.SurroundColors = @(C "0A0E15")
if (-not $NoTile) {
    $g.FillPath($bgBrush, $tile)
    $g.DrawPath((New-Object System.Drawing.Pen((C "E2B65A" 90), 3)), $tile)
} else {
    # Mark only: lens and handle fill the square.
    $g.ResetTransform()
    $k2 = $Size / 200.0
    $g.ScaleTransform($k2, $k2)
    $g.TranslateTransform(-34, -32)
}

$gold = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.PointF(40, 40)), (New-Object System.Drawing.PointF(215, 215)), (C "FCE8AE"), (C "A9772A"))
$blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
$blend.Colors = @((C "FCE8AE"), (C "E8BE5E"), (C "A9772A"))
$blend.Positions = @([single]0, [single]0.45, [single]1)
$gold.InterpolationColors = $blend

# Handle (shadow, then gold).
$shadow = New-Object System.Drawing.Pen((C "6E4C18"), 30); $shadow.StartCap = 'Round'; $shadow.EndCap = 'Round'
$g.DrawLine($shadow, 160, 158, 206, 204)
$handle = New-Object System.Drawing.Pen($gold, 24); $handle.StartCap = 'Round'; $handle.EndCap = 'Round'
$g.DrawLine($handle, 160, 158, 204, 202)

# Lens and ring.
$lens = New-Object System.Drawing.Drawing2D.GraphicsPath
$lens.AddEllipse(48, 46, 132, 132)
$lensBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($lens)
$lensBrush.CenterPoint = New-Object System.Drawing.PointF(95, 85)
$lensBrush.CenterColor = C "18253F"
$lensBrush.SurroundColors = @(C "090D16")
$g.FillPath($lensBrush, $lens)
$g.DrawEllipse((New-Object System.Drawing.Pen($gold, 20)), 48, 46, 132, 132)
$g.DrawEllipse((New-Object System.Drawing.Pen((C "FFFFFF" 18), 2)), 59, 57, 110, 110)
$glare = New-Object System.Drawing.Pen((C "FFFFFF" 46), 5); $glare.StartCap = 'Round'; $glare.EndCap = 'Round'
$g.DrawArc($glare, 68, 66, 92, 92, 200, 55)

# Role badges: blue tank, green healer, red damage.
function Badge($cx, $cy, $hex) {
    $g.FillEllipse((New-Object System.Drawing.SolidBrush((C $hex))), $cx - 16, $cy - 16, 32, 32)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush((C "FFFFFF" 40))), $cx - 11, $cy - 13, 22, 12)
    $g.DrawEllipse((New-Object System.Drawing.Pen((C "000000" 120), 1.5)), $cx - 16, $cy - 16, 32, 32)
}
Badge 114 80 "2B6FD8"
Badge 88 126 "2E9C4B"
Badge 140 126 "C3382D"
$white = New-Object System.Drawing.SolidBrush((C "F7FAFF"))
# shield
$sh = New-Object System.Drawing.Drawing2D.GraphicsPath
$sh.AddLines(@((New-Object System.Drawing.PointF(114, 70)), (New-Object System.Drawing.PointF(122, 73)), (New-Object System.Drawing.PointF(122, 79))))
$sh.AddBezier(122, 79, 122, 85, 118, 89, 114, 91)
$sh.AddBezier(114, 91, 110, 89, 106, 85, 106, 79)
$sh.AddLines(@((New-Object System.Drawing.PointF(106, 79)), (New-Object System.Drawing.PointF(106, 73))))
$sh.CloseFigure()
$g.FillPath($white, $sh)
# cross
$g.FillRectangle($white, 85.5, 117, 5, 18); $g.FillRectangle($white, 79, 123.5, 18, 5)
# sword
$sw = New-Object System.Drawing.Pen($white, 3.5); $sw.StartCap = 'Round'; $sw.EndCap = 'Triangle'
$g.DrawLine($sw, 135, 131, 148, 118)
$g.DrawLine((New-Object System.Drawing.Pen($white, 3)), 131, 125, 139, 133)
$grip = New-Object System.Drawing.Pen($white, 3); $grip.StartCap = 'Round'; $grip.EndCap = 'Round'
$g.DrawLine($grip, 134, 132, 130, 136)
$g.Dispose()

New-Item -ItemType Directory -Force $OutDir | Out-Null
$bmp.Save((Join-Path $OutDir "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)

# TGA: uncompressed 32-bit BGRA, top-left origin (descriptor 0x28).
$data = $bmp.LockBits((New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)), 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride * $Size)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$bmp.UnlockBits($data)
$header = New-Object byte[] 18
$header[2] = 2
$header[12] = $Size -band 0xFF; $header[13] = ($Size -shr 8) -band 0xFF
$header[14] = $Size -band 0xFF; $header[15] = ($Size -shr 8) -band 0xFF
$header[16] = 32; $header[17] = 0x28
$fs = [System.IO.File]::Create((Join-Path $OutDir "$Name.tga"))
$fs.Write($header, 0, 18); $fs.Write($bytes, 0, $bytes.Length); $fs.Close()
"ok"
