param(
    [string]$Version = "0.3.0",
    [string]$OutputDirectory = ""
)
$ErrorActionPreference = "Stop"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot "dist\windows" }
$stage = Join-Path $projectRoot ".build\windows-stage"
$coreDirectory = Join-Path $stage "Core"
$toolsDirectory = Join-Path $stage "Tools"
$licensesDirectory = Join-Path $stage "Licenses"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $coreDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $toolsDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $licensesDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

. (Join-Path $PSScriptRoot "enter-dev-shell.ps1")
Push-Location $projectRoot
try {
    swift build -c release
    if ($LASTEXITCODE -ne 0) { throw "Swift core build failed." }
    $swiftBinaryDirectory = swift build -c release --show-bin-path
    Copy-Item (Join-Path $swiftBinaryDirectory "FootageFlow.exe") (Join-Path $coreDirectory "FootageFlowCore.exe")

    $targetInfo = swiftc -print-target-info | ConvertFrom-Json
    $runtimeCandidates = @($targetInfo.paths.runtimeLibraryPaths) + @(
        $env:Path -split ";" | Where-Object { $_ -match "[\\/]Swift[\\/]Runtimes[\\/].*[\\/]usr[\\/]bin[\\/]?$" }
    )
    $runtimeCount = 0
    foreach ($runtimePath in ($runtimeCandidates | Select-Object -Unique)) {
        if (-not (Test-Path $runtimePath -PathType Container)) { continue }
        $runtimeFiles = Get-ChildItem $runtimePath -Filter "*.dll" -File
        $runtimeCount += $runtimeFiles.Count
        $runtimeFiles | Copy-Item -Destination $coreDirectory -Force
    }
    if ($runtimeCount -eq 0) { throw "The official Swift runtime DLLs were not found." }

    dotnet publish "Windows\FootageFlow.Windows\FootageFlow.Windows.csproj" -c Release -r win-x64 --self-contained true -p:Version=$Version -o $stage
    if ($LASTEXITCODE -ne 0) { throw "Windows interface publish failed." }

    $ytDlp = & (Join-Path $PSScriptRoot "fetch-yt-dlp.ps1")
    Copy-Item $ytDlp (Join-Path $toolsDirectory "yt-dlp.exe") -Force
    Copy-Item "LICENSE" (Join-Path $stage "LICENSE.txt")
    Copy-Item "THIRD_PARTY_NOTICES.md" (Join-Path $stage "THIRD_PARTY_NOTICES.md")

    $dotnetRoot = Split-Path (Get-Command dotnet).Source
    $dotnetLicenseDirectory = Join-Path $licensesDirectory "dotnet"
    New-Item -ItemType Directory -Path $dotnetLicenseDirectory -Force | Out-Null
    Copy-Item (Join-Path $dotnetRoot "LICENSE.txt") (Join-Path $dotnetLicenseDirectory "LICENSE.txt")
    Copy-Item (Join-Path $dotnetRoot "ThirdPartyNotices.txt") (Join-Path $dotnetLicenseDirectory "ThirdPartyNotices.txt")

    $swiftLicenseDirectory = Join-Path $licensesDirectory "swift"
    New-Item -ItemType Directory -Path $swiftLicenseDirectory -Force | Out-Null
    $swiftLicenseDestination = Join-Path $swiftLicenseDirectory "LICENSE.txt"
    $swiftBin = Split-Path (Get-Command swift).Source
    $swiftInstallRoot = (Resolve-Path (Join-Path $swiftBin "..\..\..\..")).Path
    $swiftLicense = Get-ChildItem $swiftInstallRoot -Recurse -File -Include "LICENSE.txt", "LICENSE" |
        Where-Object { Select-String -Path $_.FullName -Pattern "Runtime Library Exception" -Quiet } |
        Select-Object -First 1
    if ($swiftLicense) {
        Copy-Item $swiftLicense.FullName $swiftLicenseDestination
    } else {
        $swiftLicenseURL = "https://www.swift.org/LICENSE.txt"
        $swiftLicenseSHA256 = "167beb36f181bd163c93c6feb45c68e5f9462fe1af55b278f7bfd1df20e673a3"
        Invoke-WebRequest -Uri $swiftLicenseURL -OutFile $swiftLicenseDestination -UseBasicParsing
        $downloadedSHA256 = (Get-FileHash $swiftLicenseDestination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($downloadedSHA256 -ne $swiftLicenseSHA256) {
            Remove-Item $swiftLicenseDestination -Force
            throw "The downloaded official Swift runtime license did not match its pinned checksum."
        }
    }

    $archive = Join-Path $OutputDirectory "FootageFlow-$Version-Windows-x64-portable.zip"
    if (Test-Path $archive) { Remove-Item $archive -Force }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $archive -CompressionLevel Optimal
    (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() + "  " + (Split-Path $archive -Leaf) |
        Set-Content ($archive + ".sha256") -Encoding ascii -NoNewline
    Write-Output $stage
} finally { Pop-Location }
