<#
    optimize-images.ps1 — генерация веб-версий (WebP) из оригиналов.

    Источник метаданных: ../inventory.csv
      file       — имя файла в originals/
      slug       — имя производного файла в web/ и thumbs/
      web_q      — персональное качество WebP (если пусто — берётся -WebQuality)
      readiness  — значение duplicate пропускается

    Требуется cwebp.exe из пакета libwebp:
      https://developers.google.com/speed/webp/download

    Пример:
      .\optimize-images.ps1 -Cwebp "C:\tools\libwebp\bin\cwebp.exe"
#>
param(
    [string]$Cwebp = '',
    [int]$WebQuality = 82,
    [int]$ThumbQuality = 78,
    [int]$WebMaxLong = 1800,
    [int]$ThumbMaxLong = 600
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$inv = Join-Path $root 'inventory.csv'
if (-not (Test-Path $inv)) { throw "inventory.csv не найден: $inv" }

if (-not $Cwebp) {
    $cmd = Get-Command cwebp -ErrorAction SilentlyContinue
    if ($cmd) { $Cwebp = $cmd.Source }
}
if (-not $Cwebp -or -not (Test-Path $Cwebp)) {
    throw "cwebp.exe не найден. Скачайте libwebp и передайте путь через -Cwebp."
}

function Convert-One {
    param([string]$In, [string]$Out, [int]$Quality, [int]$MaxLong)
    $img = [System.Drawing.Image]::FromFile($In)
    $w = $img.Width; $h = $img.Height
    $img.Dispose()
    $cargs = @('-q', "$Quality", '-m', '6', '-mt')
    if ([math]::Max($w, $h) -gt $MaxLong) {
        if ($w -ge $h) { $cargs += @('-resize', "$MaxLong", '0') } else { $cargs += @('-resize', '0', "$MaxLong") }
    }
    # cwebp пишет прогресс в stderr; при ErrorActionPreference=Stop это
    # превращается в ложную terminating-ошибку. Гасим только на время вызова.
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $code = 1
    try {
        & $Cwebp @cargs $In -o $Out 2>&1 | Out-Null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $eap
    }
    if ($code -ne 0) { throw "cwebp завершился с ошибкой для $In (код $code)" }
}

$rows = Import-Csv -Path $inv -Delimiter ';'
$done = 0; $skipped = 0; $missing = 0

foreach ($r in $rows) {
    if ($r.readiness -eq 'duplicate') { $skipped++; continue }
    $in = Join-Path $root ("originals\" + $r.file)
    if (-not (Test-Path $in)) { Write-Warning "нет файла: $($r.file)"; $missing++; continue }

    $q = if ($r.web_q) { [int]$r.web_q } else { $WebQuality }

    Convert-One -In $in -Out (Join-Path $root ("web\" + $r.slug + '.webp')) -Quality $q -MaxLong $WebMaxLong
    Convert-One -In $in -Out (Join-Path $root ("thumbs\" + $r.slug + '.webp')) -Quality $ThumbQuality -MaxLong $ThumbMaxLong
    $done++
}

"Готово: обработано $done, пропущено $skipped (дубли), отсутствует $missing."
"Размеры web_kb/thumb_kb в inventory.csv — снимок на момент импорта; после пересборки они могут отличаться."
