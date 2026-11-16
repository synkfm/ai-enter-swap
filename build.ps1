# main.template.ahk + ms-ime.tsv -> main.ahk -> AIEnterSwap.exe
#   -Package を付けると、配布用の zip と SHA-256 も作る
param([switch]$Package)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$tsv = (Get-Content "$root\src\ms-ime.tsv" -Raw -Encoding utf8) -replace "`r", ''
$tpl = Get-Content "$root\src\main.template.ahk" -Raw -Encoding utf8
$msimeCustom = (Get-Content "$root\src\msime-custom.tsv" -Raw -Encoding utf8) -replace "`r", ''
$ahk = $tpl.Replace('{{MSIME_TSV}}', $tsv.TrimEnd("`n")).Replace('{{MSIME_CUSTOM}}', $msimeCustom.TrimEnd("`n"))
$utf8Bom = New-Object System.Text.UTF8Encoding $true
[IO.File]::WriteAllText("$root\main.ahk", $ahk, $utf8Bom)

$compiler = "$env:LOCALAPPDATA\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
$base = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
New-Item -ItemType Directory -Force "$root\dist" | Out-Null
& $compiler /in "$root\main.ahk" /out "$root\dist\AIEnterSwap.exe" /base $base /silent verbose | Out-Host
Write-Host "built: $root\dist\AIEnterSwap.exe"

if ($Package) {
    $ver = [regex]::Match($tpl, 'APP_VERSION := "([^"]+)"').Groups[1].Value
    $name = "AIEnterSwap-$ver"
    $dir = "$root\release\$name"
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item "$root\dist\AIEnterSwap.exe" $dir
    Copy-Item "$root\LICENSE" "$dir\LICENSE.txt"
    Copy-Item "$root\THIRD-PARTY-NOTICES.txt" $dir
    $readme = Get-Content "$root\README.md" -Raw -Encoding utf8
    [IO.File]::WriteAllText("$dir\説明書（はじめにお読みください）.txt", $readme, $utf8Bom)
    $zip = "$root\release\$name.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    # zip の中に「AIEnterSwap-x.y.z」フォルダごと入れる（日本語のファイル名が化けないよう UTF-8 で）
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipFile = 'System.IO.Compression.ZipFile' -as [type]
    $level = ('System.IO.Compression.CompressionLevel' -as [type])::Optimal
    $zipFile::CreateFromDirectory($dir, $zip, $level, $true, [Text.Encoding]::UTF8)
    Write-Host "zip:  $zip"
    Write-Host ("SHA-256 exe: " + (Get-FileHash "$dir\AIEnterSwap.exe").Hash)
    Write-Host ("SHA-256 zip: " + (Get-FileHash $zip).Hash)
}
