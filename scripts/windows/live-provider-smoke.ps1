param(
    [string]$CorePath = "",
    [string]$YtDlpPath = "",
    [string]$ReportPath = ""
)
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $CorePath) { $CorePath = Join-Path $projectRoot ".build\windows-stage\Core\FootageFlowCore.exe" }
if (-not $YtDlpPath) { $YtDlpPath = Join-Path $projectRoot ".build\windows-stage\Tools\yt-dlp.exe" }
if (-not $ReportPath) { $ReportPath = Join-Path $projectRoot "dist\windows\windows-provider-smoke.json" }

function Invoke-Core([hashtable]$Request) {
    $Request.id = [Guid]::NewGuid().ToString("N")
    $payload = $Request | ConvertTo-Json -Depth 16 -Compress
    $raw = $payload | & $CorePath --core-request
    if ($LASTEXITCODE -ne 0) { throw "The Windows core process exited unexpectedly." }
    $response = $raw | ConvertFrom-Json -Depth 16
    if (-not $response.success) { throw "Core request failed: $($response.errorCode)" }
    return $response
}

function Test-PublicProvider([string]$Provider, [string]$Query, [string]$MediaType) {
    $response = Invoke-Core @{
        action = "search"; query = $Query; mediaType = $MediaType; orientation = "all"
        resolution = "all"; duration = "all"; pageSize = 6; providerIDs = @($Provider); language = "en"
    }
    $batch = $response.providerBatches | Select-Object -First 1
    if (-not $batch -or $batch.assets.Count -lt 1) { throw "$Provider did not return a real search result." }
    $asset = $batch.assets | Select-Object -First 1
    if ($asset.sourcePageURL -notmatch '^https://') { throw "$Provider returned an invalid source page." }
    return @{ status = "passed"; mode = $batch.mode; count = $batch.assets.Count; sample = $asset.title }
}

function Test-OptionalProvider([string]$Provider, [string]$Query, [string]$MediaType, [string]$Key) {
    $request = @{
        action = "search"; query = $Query; mediaType = $MediaType; orientation = "all"
        resolution = "all"; duration = "all"; pageSize = 4; providerIDs = @($Provider); language = "en"
    }
    if (-not [string]::IsNullOrWhiteSpace($Key)) { $request.apiKeys = @{ $Provider = $Key } }
    $response = Invoke-Core $request
    $batch = $response.providerBatches | Select-Object -First 1
    if (-not $batch) { throw "$Provider did not return an isolated provider result." }
    if ([string]::IsNullOrWhiteSpace($Key) -and $batch.mode -ne "directSearch") {
        throw "$Provider did not select Direct Search without an API key."
    }
    if (-not [string]::IsNullOrWhiteSpace($Key) -and $batch.assets.Count -lt 1) {
        throw "$Provider official API did not return a result."
    }
    $status = if ($batch.assets.Count -gt 0) { "passed" } else { "graceful-$($batch.state.availability)" }
    return @{ status = $status; mode = $batch.mode; count = $batch.assets.Count; errorCode = $batch.errorCode }
}

function Test-YouTube([string]$Key) {
    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $response = Invoke-Core @{
            action = "search"; query = "bank"; mediaType = "video"; orientation = "all"
            resolution = "all"; duration = "all"; pageSize = 3; providerIDs = @("youtube")
            apiKeys = @{ youtube = $Key }; language = "en"
        }
        $batch = $response.providerBatches | Select-Object -First 1
        if (-not $batch -or $batch.assets.Count -lt 1) { throw "YouTube Data API did not return a result." }
        return @{ status = "passed"; mode = "officialAPI"; count = $batch.assets.Count }
    }

    $output = & $YtDlpPath --ignore-config --no-progress --no-warnings --flat-playlist --dump-single-json --playlist-end 1 "ytsearch1:bank" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = ($output -join "`n") | ConvertFrom-Json -Depth 16
        if ($json.entries.Count -lt 1) { throw "yt-dlp search completed without a result." }
        return @{ status = "passed"; mode = "ytDLP"; count = $json.entries.Count }
    }
    $message = ($output -join "`n")
    if ($message -match '(?i)(429|too many requests|sign in|login|captcha|temporarily blocked|javascript runtime|remote components|unable to download api)') {
        return @{ status = "graceful-best-effort-unavailable"; mode = "ytDLP"; count = 0 }
    }
    throw "yt-dlp search failed with an unclassified error."
}

$report = [ordered]@{
    generatedAt = [DateTimeOffset]::UtcNow.ToString("O")
    platform = "windows-x64"
    wikimedia = Test-PublicProvider "wikimedia" "bank" "image"
    internetArchive = Test-PublicProvider "internetArchive" "Argentina financial crisis 2001" "video"
    pexels = Test-OptionalProvider "pexels" "bank" "image" $env:PEXELS_API_KEY
    pixabay = Test-OptionalProvider "pixabay" "bank" "image" $env:PIXABAY_API_KEY
    youtube = Test-YouTube $env:YOUTUBE_API_KEY
}
New-Item -ItemType Directory -Path (Split-Path $ReportPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content $ReportPath -Encoding utf8
$report | ConvertTo-Json -Depth 8
