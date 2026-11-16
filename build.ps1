# main.template.ahk + ms-ime.tsv -> main.ahk -> ClaudeEnterSwap.exe
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
& $compiler /in "$root\main.ahk" /out "$root\dist\ClaudeEnterSwap.exe" /base $base /silent verbose | Out-Host
Write-Host "built: $root\dist\ClaudeEnterSwap.exe"
