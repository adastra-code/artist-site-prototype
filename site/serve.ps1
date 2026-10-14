<#
    serve.ps1 — локальный сервер для просмотра собранного сайта.

    Запуск:  .\serve.ps1
             .\serve.ps1 -Port 9000
    Стоп:    Ctrl+C

    Без зависимостей и без прав администратора (слушает только 127.0.0.1).
#>
param(
    [int]$Port = 8123,
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Join-Path $PSScriptRoot 'dist' }
$Root = (Resolve-Path $Root).Path

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.webp' = 'image/webp'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.xml'  = 'application/xml; charset=utf-8'
    '.txt'  = 'text/plain; charset=utf-8'
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Host "Сайт: http://127.0.0.1:$Port/   (папка: $Root, остановка — Ctrl+C)"

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
            $requestLine = $reader.ReadLine()
            if (-not $requestLine) { continue }
            while ($true) { $l = $reader.ReadLine(); if ($null -eq $l -or $l -eq '') { break } }

            $parts = $requestLine.Split(' ')
            $method = $parts[0]
            $rawPath = $parts[1]
            $path = [System.Uri]::UnescapeDataString(($rawPath -split '\?')[0])
            if ($path -eq '/') { $path = '/index.html' }

            $rel = $path.TrimStart('/') -replace '/', '\'
            $file = Join-Path $Root $rel

            $status = '200 OK'
            $ct = 'application/octet-stream'
            $body = $null

            if ($method -ne 'GET' -and $method -ne 'HEAD') {
                $status = '405 Method Not Allowed'
                $ct = 'text/plain; charset=utf-8'
                $body = [System.Text.Encoding]::UTF8.GetBytes('405')
            }
            elseif (Test-Path $file -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($file).ToLower()
                if ($mime.ContainsKey($ext)) { $ct = $mime[$ext] }
                $body = [System.IO.File]::ReadAllBytes($file)
            }
            else {
                $status = '404 Not Found'
                $ct = 'text/plain; charset=utf-8'
                $body = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
            }

            $header = "HTTP/1.1 $status`r`nContent-Type: $ct`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
            $hb = [System.Text.Encoding]::ASCII.GetBytes($header)
            $stream.Write($hb, 0, $hb.Length)
            if ($method -ne 'HEAD') { $stream.Write($body, 0, $body.Length) }
            $stream.Flush()
        }
        finally {
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}
