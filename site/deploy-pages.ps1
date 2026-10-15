<#
    deploy-pages.ps1 — сборка и публикация сайта в GitHub Pages.

    Собирает dist/ и публикует его содержимое в ветку gh-pages того же
    репозитория, откуда GitHub Pages отдаёт сайт.

    Запуск:
      .\deploy-pages.ps1 -BaseUrl "https://adastra-code.github.io/artist-site-prototype"
      .\deploy-pages.ps1 -SkipBuild        # только переопубликовать текущий dist/
#>
param(
    [string]$BaseUrl = '',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent

Push-Location $root
try { $url = (git remote get-url origin).Trim() } finally { Pop-Location }
if (-not $url) { throw "не найден remote origin — сначала добавьте его" }

if (-not $SkipBuild) {
    Write-Host "Сборка..."
    if ($BaseUrl) { & (Join-Path $here 'build.ps1') -BaseUrl $BaseUrl }
    else { & (Join-Path $here 'build.ps1') }
}

$dist = Join-Path $here 'dist'
if (-not (Test-Path (Join-Path $dist 'index.html'))) { throw "нет dist/index.html — сначала соберите сайт" }

$tmp = Join-Path $env:TEMP ("ghpages-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Copy-Item (Join-Path $dist '*') $tmp -Recurse -Force
New-Item -ItemType File -Path (Join-Path $tmp '.nojekyll') -Force | Out-Null

Push-Location $tmp
try {
    git init -b gh-pages -q
    git add -A
    git -c user.name="deploy" -c user.email="deploy@localhost" commit -q -m "Deploy prototype site"
    git remote add origin $url
    git push -f origin gh-pages
}
finally {
    Pop-Location
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Опубликовано: ветка gh-pages в $url"
