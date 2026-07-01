<#
  MakeIcon.ps1 — render the Crisp waveform mark to a multi-resolution .ico, tinted
  per channel. The Windows counterpart of the macOS Scripts/MakeIcon.swift: a
  rounded-square app tile (channel accent) with the white waveform on top.

    stable  -> blue   (#0A84FF)
    nightly -> amber  (#FF9F0A)
    dev     -> purple (#BF5AF2)

  Usage:  pwsh Scripts/MakeIcon.ps1 -Channel dev -OutPath Assets/AppIcon-Dev.ico
#>
param(
    [ValidateSet('stable', 'nightly', 'dev')] [string]$Channel = 'stable',
    [Parameter(Mandatory)] [string]$OutPath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$accent = switch ($Channel) {
    'nightly' { [System.Drawing.Color]::FromArgb(0xFF, 0xFF, 0x9F, 0x0A) }
    'dev'     { [System.Drawing.Color]::FromArgb(0xFF, 0xBF, 0x5A, 0xF2) }
    default   { [System.Drawing.Color]::FromArgb(0xFF, 0x0A, 0x84, 0xFF) }
}
# The waveform bar heights (out of 40), matching Views/Controls/WaveformMark.axaml.
$bars = 14, 24, 36, 20, 40, 28, 16, 32, 22
$barW = 4; $gap = 3; $designW = ($bars.Count * $barW) + (($bars.Count - 1) * $gap); $designH = 40

function New-RoundedPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-IconBitmap([int]$S) {
    $bmp = New-Object System.Drawing.Bitmap $S, $S
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Rounded-square accent tile.
    $inset = $S * 0.055
    $tileR = $S * 0.18
    $tile = New-RoundedPath $inset $inset ($S - 2 * $inset) ($S - 2 * $inset) $tileR
    $brush = New-Object System.Drawing.SolidBrush $accent
    $g.FillPath($brush, $tile)

    # White waveform, scaled to fit ~62% of the tile width, vertically centered.
    $targetW = ($S - 2 * $inset) * 0.62
    $scale = $targetW / $designW
    $x = ($S - $targetW) / 2.0
    $cy = $S / 2.0
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    foreach ($bh in $bars) {
        $w = $barW * $scale
        $h = $bh * $scale
        $bar = New-RoundedPath $x ($cy - $h / 2.0) $w $h ($w / 2.0)
        $g.FillPath($white, $bar)
        $x += ($barW + $gap) * $scale
    }
    $g.Dispose()
    return $bmp
}

# Pack PNG-encoded images into a single .ico (Vista+ supports embedded PNGs).
$sizes = 16, 24, 32, 48, 64, 128, 256
$pngs = foreach ($s in $sizes) {
    $bmp = New-IconBitmap $s
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}

# Resolve a relative OutPath against the project dir (apps/desktop-win), not the
# caller's current directory, so it lands in the right place from any cwd.
$resolved = if ([System.IO.Path]::IsPathRooted($OutPath)) { $OutPath }
            else { Join-Path (Split-Path $PSScriptRoot -Parent) $OutPath }
$full = [System.IO.Path]::GetFullPath($resolved)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($full)) | Out-Null
$fs = [System.IO.File]::Create($full)
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)   # ICONDIR
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $len = $pngs[$i].Length
    $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))   # width  (0 = 256)
    $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))   # height
    $bw.Write([byte]0); $bw.Write([byte]0)                    # colors, reserved
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)               # planes, bpp
    $bw.Write([UInt32]$len); $bw.Write([UInt32]$offset)       # size, offset
    $offset += $len
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Flush(); $bw.Dispose(); $fs.Dispose()
Write-Host "Wrote $full ($Channel)"
