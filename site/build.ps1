<#
    build.ps1 — генератор статического сайта (прототип, русская версия).

    Читает:
      content/ru.json    — интерфейсные тексты (позже добавятся en.json, zh.json)
      content/works.csv  — работы: слаг, название, серия, год, техника, размер, цена
      ../assets/works/   — изображения (web/ и thumbs/)

    Пишет:
      dist/  — готовый статический сайт

    Запуск:
      .\build.ps1
      .\build.ps1 -BaseUrl "https://имя-художницы.ru"
#>
param(
    [string]$Out = '',
    [string]$BaseUrl = 'https://example.ru',
    [switch]$NoIndex
)

$ErrorActionPreference = 'Stop'

$here    = $PSScriptRoot
$root    = Split-Path $here -Parent
$content = Join-Path $here 'content'
$srcDir  = Join-Path $here 'src'
if (-not $Out) { $Out = Join-Path $here 'dist' }
$outAbs  = $Out.TrimEnd('\', '/')
$imgRoot = Join-Path $root 'assets/works'

if (-not (Test-Path (Join-Path $content 'ru.json')))    { throw "нет content/ru.json" }
if (-not (Test-Path (Join-Path $content 'works.csv')))  { throw "нет content/works.csv" }

$t     = Get-Content (Join-Path $content 'ru.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$works = @(Import-Csv (Join-Path $content 'works.csv') -Delimiter ';' -Encoding UTF8 | Sort-Object { [int]$_.order })

# Реальные размеры изображений берём из каталога работ — иначе браузер
# зарезервирует неверное место и верстка «прыгнет» при загрузке.
$inv = @{}
$invPath = Join-Path $root 'assets/works/inventory.csv'
if (-not (Test-Path $invPath)) { throw "нет assets/works/inventory.csv" }
foreach ($r in (Import-Csv $invPath -Delimiter ';' -Encoding UTF8)) {
    $inv[$r.slug] = @{ w = [int]$r.width; h = [int]$r.height }
}

function Src-Dims([string]$slug) {
    if ($inv.ContainsKey($slug)) { return $inv[$slug] }
    return @{ w = 1200; h = 800 }
}
function Fit-Dims([string]$slug, [int]$maxLong) {
    $d = Src-Dims $slug
    $m = [math]::Max($d.w, $d.h)
    if ($m -le $maxLong -or $m -eq 0) { return @{ w = $d.w; h = $d.h } }
    $s = $maxLong / $m
    return @{ w = [int][math]::Round($d.w * $s); h = [int][math]::Round($d.h * $s) }
}
function Thumb-Dims([string]$slug) { return (Fit-Dims $slug 600) }
function Web-Dims([string]$slug)   { return (Fit-Dims $slug 1800) }

function Esc([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}

function MetaLine($w) {
    $parts = @()
    if ($w.year)      { $parts += $w.year }
    if ($w.technique) { $parts += $w.technique }
    if ($w.size)      { $parts += $w.size }
    return ($parts -join ' &middot; ')
}

function ImgSrcset([string]$slug) {
    return "assets/img/thumbs/$slug.webp 600w, assets/img/web/$slug.webp 1800w"
}

# ------------------------------------------------------------------ каркас

function Get-Header([string]$active) {
    $nav = ''
    foreach ($item in $t.nav) {
        $cur = ''
        if ($item.href -eq $active) { $cur = ' aria-current="page"' }
        $nav += "        <a href=""$(Esc $item.href)""$cur>$(Esc $item.label)</a>`n"
    }
    $langs = ''
    foreach ($l in $t.langs) {
        if ($l.active) {
            $langs += "        <a class=""is-active"" href=""$(Esc $l.href)"" hreflang=""$($l.code)"">$(Esc $l.label)</a>`n"
        } else {
            $langs += "        <span class=""is-off"" title=""$($t.footer.langNote)"" aria-disabled=""true"">$(Esc $l.label)</span>`n"
        }
    }
    $name = Esc $t.site.name
    $role = Esc $t.site.role
    return @"
  <a class="skip" href="#content">$(Esc $t.ui.skipToContent)</a>
  <header class="site-header">
    <div class="wrap">
      <a class="brand" href="index.html">
        <span class="name">$name</span>
        <span class="role">$role</span>
      </a>
      <nav class="site-nav" aria-label="$(Esc $t.ui.menu)">
$nav      </nav>
      <nav class="langs" aria-label="Язык">
$langs      </nav>
    </div>
  </header>
"@
}

function Get-Footer {
    $email = Esc $t.site.email
    # Телефон и соцсети выводятся только если заполнены в content/ru.json.
    $extra = ''
    if ($t.site.phone)     { $extra += "          <p>$(Esc $t.site.phone)</p>`n" }
    if ($t.site.instagram) { $extra += "          <p><a href=""https://instagram.com/"">$(Esc $t.site.instagram)</a></p>`n" }
    return @"
  <footer class="site-footer" id="contact">
    <div class="wrap">
      <div class="cols">
        <div>
          <h3 class="serif">$(Esc $t.footer.contactsTitle)</h3>
          <p><a href="mailto:$email">$email</a></p>
$extra        </div>
        <div class="subscribe">
          <h3 class="serif">$(Esc $t.home.subscribeTitle)</h3>
          <form action="#" method="post">
            <label class="skip" for="email">$(Esc $t.home.subscribePlaceholder)</label>
            <input id="email" type="email" name="email" placeholder="$(Esc $t.home.subscribePlaceholder)" required>
            <button type="submit">$(Esc $t.home.subscribeCta)</button>
          </form>
        </div>
      </div>
      <p class="legal">$(Esc $t.footer.rights)</p>
      <p class="note">$(Esc $t.footer.langNote)</p>
    </div>
  </footer>
"@
}

function Get-Head([string]$title, [string]$desc, [string]$canonicalPath, [string]$ogImage) {
    $full = "$BaseUrl/$canonicalPath"
    $robotsMeta = if ($NoIndex) { 'noindex, nofollow' } else { 'index, follow' }
    return @"
<!doctype html>
<html lang="$($t.lang)">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<meta name="description" content="$desc">
<meta name="robots" content="$robotsMeta">
<link rel="canonical" href="$full">
<!-- hreflang: добавится вместе с en/zh, когда появятся /en/ и /zh/ -->
<meta property="og:type" content="website">
<meta property="og:site_name" content="$(Esc $t.site.name)">
<meta property="og:title" content="$title">
<meta property="og:description" content="$desc">
<meta property="og:url" content="$full">
$(if ($ogImage) { "<meta property=""og:image"" content=""$BaseUrl/$ogImage"">" })
<link rel="stylesheet" href="assets/css/style.css">
</head>
"@
}

function Get-WorkFigure($w) {
    $slug = Esc $w.slug
    $title = Esc $w.title
    $meta = MetaLine $w
    $metaHtml = ''
    if ($meta) { $metaHtml = "<span class=""meta"">$meta</span>" }
    $td = Thumb-Dims $w.slug
    return @"
        <figure class="work">
          <a href="$slug.html">
            <img src="assets/img/thumbs/$slug.webp" srcset="$(ImgSrcset $w.slug)"
                 sizes="(max-width:620px) 92vw, (max-width:980px) 45vw, 30vw"
                 width="$($td.w)" height="$($td.h)" loading="lazy" decoding="async" alt="$title">
            <figcaption>
              <span class="title">$title</span>
              $metaHtml
            </figcaption>
          </a>
        </figure>
"@
}

function Get-WorkPage($w, $prev, $next) {
    $slug = Esc $w.slug
    $title = Esc $w.title
    $spec = ''
    if ($w.year)      { $spec += "          <dt>$(Esc $t.work.fields.year)</dt><dd>$(Esc $w.year)</dd>`n" }
    if ($w.technique) { $spec += "          <dt>$(Esc $t.work.fields.technique)</dt><dd>$(Esc $w.technique)</dd>`n" }
    if ($w.size)      { $spec += "          <dt>$(Esc $t.work.fields.size)</dt><dd>$(Esc $w.size)</dd>`n" }
    $status = if ($w.available -eq 'yes') { Esc $t.work.available } else { Esc $t.work.sold }
    $price  = if ($w.price) { Esc $w.price } else { Esc $t.work.priceOnRequest }
    $spec += "          <dt>Статус</dt><dd>$status</dd>`n          <dt>Цена</dt><dd>$price</dd>`n"

    $prevLink = if ($prev) { "<a href=""$(Esc $prev.slug).html"">&larr; $(Esc $prev.title)</a>" } else { "<span></span>" }
    $nextLink = if ($next) { "<a href=""$(Esc $next.slug).html"">$(Esc $next.title) &rarr;</a>" } else { "<span></span>" }
    $wd = Web-Dims $w.slug

    return @"
      <main id="content" class="work-page fade-in">
        <div class="wrap">
          <a class="back" href="works.html">&larr; $(Esc $t.work.back)</a>
          <figure class="stage">
            <img src="assets/img/web/$slug.webp" width="$($wd.w)" height="$($wd.h)" decoding="async" alt="$title">
          </figure>
          <div class="caption">
            <div>
              <h1>$title</h1>
            </div>
            <div>
              <dl class="spec">
$spec              </dl>
              <p style="margin-top:26px"><a class="btn" href="mailto:$(Esc $t.site.email)?subject=$title">$(Esc $t.work.inquire)</a></p>
            </div>
          </div>
          <div class="pager">
            $prevLink
            $nextLink
          </div>
        </div>
      </main>
"@
}

function Save-Page([string]$file, [string]$body) {
    [System.IO.File]::WriteAllText((Join-Path $outAbs $file), $body, (New-Object System.Text.UTF8Encoding($false)))
}

# ------------------------------------------------------------------ подготовка dist

if (Test-Path $outAbs) { Remove-Item $outAbs -Recurse -Force }
foreach ($d in 'assets/css', 'assets/img/web', 'assets/img/thumbs') {
    New-Item -ItemType Directory -Path (Join-Path $outAbs $d) -Force | Out-Null
}
Copy-Item (Join-Path $srcDir 'style.css') (Join-Path $outAbs 'assets/css/style.css') -Force

$usedSlugs = @($works | ForEach-Object { $_.slug }) + @('studio-01', 'process-01')
foreach ($s in $usedSlugs) {
    foreach ($sub in 'web', 'thumbs') {
        $from = Join-Path $imgRoot "$sub/$s.webp"
        if (-not (Test-Path $from)) { throw "нет изображения: $sub/$s.webp" }
        Copy-Item $from (Join-Path $outAbs "assets/img/$sub/$s.webp") -Force
    }
}

# ------------------------------------------------------------------ страницы

$hero = $works | Where-Object { $_.slug -eq $t.home.heroSlug } | Select-Object -First 1
if (-not $hero) { throw "heroSlug '$($t.home.heroSlug)' не найден в works.csv" }

$selected = @($works | Where-Object { $_.slug -ne $hero.slug } | Select-Object -First 6)
$available = @($works | Where-Object { $_.available -eq 'yes' })

# --- index
$selectedHtml = ''
foreach ($w in $selected) { $selectedHtml += Get-WorkFigure $w }

$avTeaser = ''
foreach ($w in ($available | Select-Object -First 3)) { $avTeaser += Get-WorkFigure $w }

$heroCaption = MetaLine $hero
$heroDims = Web-Dims $hero.slug
$studioDims = Web-Dims 'studio-01'
$processDims = Web-Dims 'process-01'
$indexTitle = "$(Esc $t.site.name) — $(Esc $t.site.titleSuffix)"
$indexBody = @"
$(Get-Head $indexTitle "$(Esc $t.home.heroText)" 'index.html' "assets/img/web/$($hero.slug).webp")
<body>
$(Get-Header 'index.html')
  <main id="content" class="fade-in">
    <section class="hero" style="border-top:0">
      <div class="wrap">
        <h1 class="hero-name">$(Esc $t.site.name)</h1>
        <p class="lead">$(Esc $t.home.heroText)</p>
        <p class="kicker">$(Esc $t.home.heroKicker)</p>
        <figure>
          <img src="assets/img/web/$($hero.slug).webp" width="$($heroDims.w)" height="$($heroDims.h)" decoding="async" alt="$(Esc $hero.title)">
          <figcaption>
            <span><a class="link" href="$(Esc $hero.slug).html">$(Esc $hero.title)</a></span>
            <span>$heroCaption</span>
          </figcaption>
        </figure>
        <div class="actions">
          <a class="btn" href="works.html">$(Esc $t.home.heroCta)</a>
          <a class="link" href="available.html">$(Esc $t.home.availableCta)</a>
        </div>
      </div>
    </section>

    <section>
      <div class="wrap">
        <div class="section-head">
          <h2 class="serif">$(Esc $t.home.selectedTitle)</h2>
          <p>$(Esc $t.home.selectedText)</p>
        </div>
        <div class="masonry">
$selectedHtml        </div>
      </div>
    </section>

    <section>
      <div class="wrap">
        <div class="section-head">
          <h2 class="serif">$(Esc $t.home.availableTitle)</h2>
          <p>$(Esc $t.home.availableText)</p>
        </div>
        <div class="masonry">
$avTeaser        </div>
        <p style="margin-top:30px"><a class="btn" href="available.html">$(Esc $t.home.availableCta)</a></p>
      </div>
    </section>

    <section>
      <div class="wrap">
        <div class="section-head">
          <h2 class="serif">$(Esc $t.home.studioTitle)</h2>
          <p>$(Esc $t.home.studioText)</p>
        </div>
        <div class="masonry">
          <figure class="work"><img src="assets/img/web/studio-01.webp" width="$($studioDims.w)" height="$($studioDims.h)" loading="lazy" decoding="async" alt="Мастерская"></figure>
          <figure class="work"><img src="assets/img/web/process-01.webp" width="$($processDims.w)" height="$($processDims.h)" loading="lazy" decoding="async" alt="Процесс работы"></figure>
        </div>
      </div>
    </section>

    <section>
      <div class="wrap prose">
        <h2 class="serif">$(Esc $t.home.aboutTitle)</h2>
        <p>$(Esc $t.home.aboutText)</p>
        <p><a class="link" href="about.html">$(Esc $t.home.aboutCta)</a></p>
      </div>
    </section>
  </main>
$(Get-Footer)
</body>
</html>
"@
Save-Page 'index.html' $indexBody

# --- works
$painting = @($works | Where-Object { $_.series -eq 'painting' })
$wc       = @($works | Where-Object { $_.series -eq 'watercolour' })
$paintHtml = ''; foreach ($w in $painting) { $paintHtml += Get-WorkFigure $w }
$wcHtml = '';    foreach ($w in $wc)       { $wcHtml += Get-WorkFigure $w }

$worksBody = @"
$(Get-Head "$(Esc $t.works.pageTitle) — $(Esc $t.site.name)" "$(Esc $t.works.intro)" 'works.html' '')
<body>
$(Get-Header 'works.html')
  <main id="content" class="fade-in">
    <section style="border-top:0">
      <div class="wrap">
        <h1>$(Esc $t.works.pageTitle)</h1>
        <p class="wrap" style="padding:0;color:var(--muted)">$(Esc $t.works.intro)</p>
      </div>
    </section>
    <section id="painting">
      <div class="wrap">
        <div class="section-head"><h2 class="serif">$(Esc $t.works.paintingTitle)</h2></div>
        <div class="masonry">
$paintHtml        </div>
      </div>
    </section>
    <section id="watercolour">
      <div class="wrap">
        <div class="section-head"><h2 class="serif">$(Esc $t.works.watercolourTitle)</h2></div>
        <div class="masonry">
$wcHtml        </div>
      </div>
    </section>
  </main>
$(Get-Footer)
</body>
</html>
"@
Save-Page 'works.html' $worksBody

# --- available
$avHtml = ''
foreach ($w in $available) { $avHtml += Get-WorkFigure $w }
$availableBody = @"
$(Get-Head "$(Esc $t.available.pageTitle) — $(Esc $t.site.name)" "$(Esc $t.available.intro)" 'available.html' '')
<body>
$(Get-Header 'available.html')
  <main id="content" class="fade-in">
    <section style="border-top:0">
      <div class="wrap">
        <h1>$(Esc $t.available.pageTitle)</h1>
        <p style="color:var(--muted);max-width:60ch">$(Esc $t.available.intro)</p>
        <div class="masonry" style="margin-top:34px">
$avHtml        </div>
        <p style="margin-top:36px"><a class="btn" href="mailto:$(Esc $t.site.email)">$(Esc $t.work.inquire)</a></p>
      </div>
    </section>
  </main>
$(Get-Footer)
</body>
</html>
"@
Save-Page 'available.html' $availableBody

# --- about
$paras = ''
foreach ($p in $t.about.paragraphs) { $paras += "        <p>$(Esc $p)</p>`n" }
$cv = ''
foreach ($c in $t.about.cv) { $cv += "          <li>$(Esc $c)</li>`n" }
$aboutBody = @"
$(Get-Head "$(Esc $t.about.pageTitle) — $(Esc $t.site.name)" "$(Esc $t.about.pageTitle) — $(Esc $t.site.name), $(Esc $t.site.city)" 'about.html' '')
<body>
$(Get-Header 'about.html')
  <main id="content" class="fade-in">
    <section style="border-top:0">
      <div class="wrap prose">
        <h1>$(Esc $t.about.pageTitle)</h1>
$paras      </div>
    </section>
    <section>
      <div class="wrap prose">
        <h2 class="serif">$(Esc $t.about.cvTitle)</h2>
        <ul>
$cv        </ul>
      </div>
    </section>
  </main>
$(Get-Footer)
</body>
</html>
"@
Save-Page 'about.html' $aboutBody

# --- work pages
for ($i = 0; $i -lt $works.Count; $i++) {
    $w = $works[$i]
    $prev = if ($i -gt 0) { $works[$i - 1] } else { $null }
    $next = if ($i -lt $works.Count - 1) { $works[$i + 1] } else { $null }
    $desc = "$(Esc $w.title) — $(MetaLine $w)"
    $body = @"
$(Get-Head "$(Esc $w.title) — $(Esc $t.site.name)" "$desc" "$($w.slug).html" "assets/img/web/$($w.slug).webp")
<body>
$(Get-Header '')
$(Get-WorkPage $w $prev $next)
$(Get-Footer)
</body>
</html>
"@
    Save-Page "$($w.slug).html" $body
}

# --- robots.txt и sitemap.xml
$pages = @('index.html', 'works.html', 'available.html', 'about.html') + @($works | ForEach-Object { "$($_.slug).html" })

if ($NoIndex) {
    # Черновик: закрыт от поисковиков. sitemap не создаём — он бы рекламировал URL.
    Save-Page 'robots.txt' "User-agent: *`nDisallow: /`n"
}
else {
    Save-Page 'robots.txt' "User-agent: *`nAllow: /`n`nSitemap: $BaseUrl/sitemap.xml`n"
    $urls = ''
    foreach ($p in $pages) { $urls += "  <url><loc>$BaseUrl/$p</loc></url>`n" }
    $sitemap = "<?xml version=""1.0"" encoding=""UTF-8""?>`n<urlset xmlns=""http://www.sitemaps.org/schemas/sitemap/0.9"">`n$urls</urlset>`n"
    Save-Page 'sitemap.xml' $sitemap
}

# ------------------------------------------------------------------ итог

$files = Get-ChildItem $outAbs -Recurse -File
"Собрано: $($files.Count) файлов, {0:N0} КБ" -f (($files | Measure-Object Length -Sum).Sum / 1KB)
"Страниц: $($pages.Count); работ: $($works.Count); доступных: $($available.Count)"
"BaseUrl: $BaseUrl"
"Индексация: " + $(if ($NoIndex) { 'закрыта (noindex + Disallow: /)' } else { 'открыта' })
