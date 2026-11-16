# src\icon.ico（16〜256px）と、確認用の preview.png を作る
# 白黒の Enter キー（日本語キーボードの逆L字）に「↵」
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot

function New-IconBitmap([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)

    # 日本語キーボードの Enter キー（逆L字）の形。白いキーに黒いふち
    function P($x, $y) { New-Object System.Drawing.PointF ($s * $x), ($s * $y) }
    $shape = [System.Drawing.PointF[]]@((P 0.12 0.10), (P 0.90 0.10), (P 0.90 0.90), (P 0.34 0.90), (P 0.34 0.50), (P 0.12 0.50))
    $bw = [Math]::Max(1.5, $s * 0.075)
    $edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), $bw
    $edge.LineJoin = 'Round'
    # キーの厚み（下にずらした黒い影）
    $drop = [Math]::Max(1.0, $s * 0.04)
    $shadow = [System.Drawing.PointF[]]($shape | ForEach-Object { New-Object System.Drawing.PointF $_.X, ($_.Y + $drop) })
    $g.FillPolygon([System.Drawing.Brushes]::Black, $shadow)
    $g.DrawPolygon($edge, $shadow)
    $g.FillPolygon([System.Drawing.Brushes]::White, $shape)
    $g.DrawPolygon($edge, $shape)

    # ↵ の矢印（黒）
    $pw = [Math]::Max(1.6, $s * 0.085)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black), $pw
    $pen.StartCap = 'Round'; $pen.LineJoin = 'Round'
    $x1 = $s * 0.72; $y1 = $s * 0.26; $y2 = $s * 0.68; $x2 = $s * 0.54
    $g.DrawLines($pen, [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF $x1, $y1),
        (New-Object System.Drawing.PointF $x1, $y2),
        (New-Object System.Drawing.PointF $x2, $y2)))
    $ah = $s * 0.12
    $tri = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ($s * 0.42), $y2),
        (New-Object System.Drawing.PointF ($x2 + $pw * 0.2), ($y2 - $ah)),
        (New-Object System.Drawing.PointF ($x2 + $pw * 0.2), ($y2 + $ah)))
    $g.FillPolygon([System.Drawing.Brushes]::Black, $tri)
    $g.Dispose()
    return $bmp
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$pngs = foreach ($s in $sizes) {
    $bmp = New-IconBitmap $s
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    if ($s -eq 256) { $bmp.Save("$root\tools\preview.png", [System.Drawing.Imaging.ImageFormat]::Png) }
    $bmp.Dispose()
    ,$ms.ToArray()
}

# ICO（中身はPNG。Windows Vista 以降で使える形式）
$out = [System.IO.MemoryStream]::new()
$bw = [System.IO.BinaryWriter]::new([System.IO.Stream]$out)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $len = $pngs[$i].Length
    $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))
    $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$len); $bw.Write([uint32]$offset)
    $offset += $len
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Flush()
[IO.File]::WriteAllBytes("$root\src\icon.ico", $out.ToArray())

# 小さいサイズの見え方を確認する一覧画像（16/24/32/48 を拡大して並べる）
$sheet = New-Object System.Drawing.Bitmap 560, 200
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::FromArgb(255, 240, 240, 240))
$g.InterpolationMode = 'NearestNeighbor'
$x = 10
foreach ($s in 16, 24, 32, 48) {
    $b = New-IconBitmap $s
    $g.DrawImage($b, $x, 10, $s * 3, $s * 3)
    $g.DrawImage($b, $x, 170, $s, $s)
    $x += $s * 3 + 20
    $b.Dispose()
}
$g.Dispose()
$sheet.Save("$root\tools\preview-small.png", [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "icon: $root\src\icon.ico"
