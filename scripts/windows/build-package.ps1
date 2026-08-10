param(
    [string]$Version = "0.2.0",
    [string]$OutputDirectory = ""
)
$ErrorActionPreference = "Stop"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot "dist\windows" }
$stage = Join-Path $projectRoot ".build\windows-stage"
$coreDirectory = Join-Path $stage "Core"
$toolsDirectory = Join-Path $stage "Tools"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $coreDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $toolsDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

. (Join-Path $PSScriptRoot "enter-dev-shell.ps1")
Push-Location $projectRoot
try {
    swift build -c release
    if ($LASTEXITCODE -ne 0) { throw "Swift core build failed." }
    $swiftBinaryDirectory = swift build -c release --show-bin-path
    Copy-Item (Join-Path $swiftBinaryDirectory "FootageFlow.exe") (Join-Path $coreDirectory "FootageFlowCore.exe")

    $targetInfo = swiftc -print-target-info | ConvertFrom-Json
    foreach ($runtimePath in $targetInfo.paths.runtimeLibraryPaths) {
        Get-ChildItem $runtimePath -Filter "*.dll" -File | Copy-Item -Destination $coreDirectory -Force
    }

    dotnet publish "Windows\FootageFlow.Windows\FootageFlow.Windows.csproj" -c Release -r win-x64 --self-contained true -p:Version=$Version -o $stage
    if ($LASTEXITCODE -ne 0) { throw "Windows interface publish failed." }

    $ytDlp = & (Join-Path $PSScriptRoot "fetch-yt-dlp.ps1")
    Copy-Item $ytDlp (Join-Path $toolsDirectory "yt-dlp.exe") -Force
    Copy-Item "LICENSE" (Join-Path $stage "LICENSE.txt")
    Copy-Item "THIRD_PARTY_NOTICES.md" (Join-Path $stage "THIRD_PARTY_NOTICES.md")

    $archive = Join-Path $OutputDirectory "FootageFlow-$Version-Windows-x64-portable.zip"
    if (Test-Path $archive) { Remove-Item $archive -Force }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $archive -CompressionLevel Optimal
    (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() + "  " + (Split-Path $archive -Leaf) |
        Set-Content ($archive + ".sha256") -Encoding ascii
    Write-Output $stage
} finally { Pop-Location }
