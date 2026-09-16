param([string]$DestinationDirectory = "")
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $DestinationDirectory) {
    $DestinationDirectory = Join-Path $projectRoot ".build\tools\ffmpeg-n8.1.2-53-g1005b294ff-windows-x64-gpl"
}
$releaseTag = "autobuild-2026-09-15-13-18"
$asset = "ffmpeg-n8.1.2-53-g1005b294ff-win64-gpl-8.1.zip"
$expected = "577a6a46f9c844657ac849245487a56dfc0507f9bac3f92d40370ebfb64ace72"
$url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/$releaseTag/$asset"
$ffmpeg = Join-Path $DestinationDirectory "ffmpeg.exe"
$ffprobe = Join-Path $DestinationDirectory "ffprobe.exe"
if ((Test-Path $ffmpeg -PathType Leaf) -and (Test-Path $ffprobe -PathType Leaf) -and
    (Test-Path (Join-Path $DestinationDirectory "LICENSE.txt") -PathType Leaf)) {
    Write-Output $DestinationDirectory
    exit 0
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("FootageFlow-ffmpeg-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $archive = Join-Path $temporary $asset
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
        throw "FFmpeg archive checksum verification failed."
    }
    $expanded = Join-Path $temporary "expanded"
    Expand-Archive -Path $archive -DestinationPath $expanded
    $root = Get-ChildItem $expanded -Directory | Select-Object -First 1
    if (-not $root) { throw "FFmpeg archive layout is invalid." }
    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    Copy-Item (Join-Path $root.FullName "bin\ffmpeg.exe") $ffmpeg -Force
    Copy-Item (Join-Path $root.FullName "bin\ffprobe.exe") $ffprobe -Force
    $license = Get-ChildItem $root.FullName -Recurse -File -Include "COPYING.GPLv3","COPYING.GPLv2","LICENSE.txt" |
        Select-Object -First 1
    if (-not $license) { throw "FFmpeg GPL license was not found in the archive." }
    Copy-Item $license.FullName (Join-Path $DestinationDirectory "LICENSE.txt") -Force
    @"
BtbN FFmpeg GPL build
Release: $releaseTag
Asset: $asset
SHA-256: $expected
Source and build scripts: https://github.com/BtbN/FFmpeg-Builds
FFmpeg source: https://ffmpeg.org/
"@ | Set-Content (Join-Path $DestinationDirectory "README.txt") -Encoding utf8
} finally {
    Remove-Item $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output $DestinationDirectory
