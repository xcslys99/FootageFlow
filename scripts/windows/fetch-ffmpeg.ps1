param([string]$DestinationDirectory = "")
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $DestinationDirectory) {
    $DestinationDirectory = Join-Path $projectRoot ".build\tools\ffmpeg-8.1.2-windows-x64-gpl"
}
$releaseTag = "autobuild-2026-08-11-13-11"
$asset = "ffmpeg-n8.1.2-34-g9b6c8969e0-win64-gpl-8.1.zip"
$expected = "05eedc113542be39af5d0f78f0b1093bafb89c98cecf25b77e8644670293107f"
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
Source and build scripts: https://github.com/BtbN/FFmpeg-Builds
FFmpeg source: https://ffmpeg.org/
"@ | Set-Content (Join-Path $DestinationDirectory "README.txt") -Encoding utf8
} finally {
    Remove-Item $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output $DestinationDirectory
