param([string]$Destination = "")
$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $Destination) { $Destination = Join-Path $projectRoot ".build\inno-7.0.2" }
$compiler = Join-Path $Destination "ISCC.exe"
if (Test-Path $compiler -PathType Leaf) { Write-Output $compiler; exit 0 }

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("FootageFlow-Inno-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
try {
    Push-Location $temporaryDirectory
    gh release download "is-7_0_2" --repo "jrsoftware/issrc" --pattern "innosetup-7.0.2-x64.exe"
    if ($LASTEXITCODE -ne 0) { throw "The verified Inno Setup package could not be downloaded." }
    $installer = Join-Path $temporaryDirectory "innosetup-7.0.2-x64.exe"
    $signature = Get-AuthenticodeSignature $installer
    if ($signature.Status -ne "Valid" -or $signature.SignerCertificate.Subject -notmatch "Pyrsys B\.V\.") {
        throw "The Inno Setup Authenticode signature is not valid."
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $arguments = @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CURRENTUSER", "/DIR=`"$Destination`"")
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0 -or -not (Test-Path $compiler -PathType Leaf)) {
        throw "Inno Setup installation failed with exit code $($process.ExitCode)."
    }
} finally {
    Pop-Location -ErrorAction SilentlyContinue
    Remove-Item $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output $compiler
