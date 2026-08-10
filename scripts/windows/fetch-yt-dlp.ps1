param([string]$Destination = "")
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $Destination) { $Destination = Join-Path $projectRoot ".build\tools\yt-dlp.exe" }
$version = "2026.07.04"
$expected = "52fe3c26dcf71fbdc85b528589020bb0b8e383155cfa81b64dd447bbe35e24b8"
$url = "https://github.com/yt-dlp/yt-dlp/releases/download/$version/yt-dlp.exe"

function Test-Tool([string]$Path) {
    (Test-Path $Path -PathType Leaf) -and ((Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expected)
}

if (Test-Tool $Destination) { Write-Output $Destination; exit 0 }
$destinationDirectory = Split-Path $Destination
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("FootageFlow-yt-dlp-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
try {
    $temporaryTool = Join-Path $temporaryDirectory "yt-dlp.exe"
    Invoke-WebRequest -Uri $url -OutFile $temporaryTool -UseBasicParsing
    if (-not (Test-Tool $temporaryTool)) { throw "yt-dlp checksum verification failed." }
    Copy-Item $temporaryTool $Destination -Force
} finally {
    Remove-Item $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output $Destination
