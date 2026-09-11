# MaoJuan - stage and deploy the promo site to Cloudflare Pages
#
# What it does:
#   1. builds a staging dir (build/promo_deploy) from promo/ (page + logo)
#   2. copies the Windows installers from dist/ into download/ with ASCII
#      names (Cloudflare strips non-ASCII, so Chinese filenames are useless)
#   3. checks every file against the Pages 25 MiB per-file limit
#   4. uploads with wrangler (unless -Stage is given)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\deploy_promo.ps1            # deploy
#   powershell -ExecutionPolicy Bypass -File tools\deploy_promo.ps1 -Stage     # only stage
#
# Auth (for the upload step) - set these two env vars first:
#   $env:CLOUDFLARE_API_TOKEN  = '...'   # Account > Cloudflare Pages > Edit
#   $env:CLOUDFLARE_ACCOUNT_ID = '...'
#
param(
    [string]$Project = 'maojuan',
    [string]$Branch = 'main',
    [switch]$Stage,
    [switch]$NoSizeCheck
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$promo = Join-Path $root 'promo'
$dist = Join-Path $root 'dist'
$stageDir = Join-Path $root 'build\promo_deploy'

# Cloudflare Pages hard limit: 25 MiB per file
$LIMIT = 25 * 1024 * 1024

function Write-Step($n, $msg) { Write-Host ("[{0}/4] {1}" -f $n, $msg) }

# ---- read the version + the expected asset names straight from index.html -------
$idx = Join-Path $promo 'index.html'
if (-not (Test-Path $idx)) { throw "promo/index.html not found" }
$html = [System.IO.File]::ReadAllText($idx, [System.Text.Encoding]::UTF8)

$verMatch = [regex]::Match($html, 'version:\s*"([0-9.]+)"')
if (-not $verMatch.Success) { throw "cannot read version from the window.MAOJUAN block in promo/index.html" }
$version = $verMatch.Groups[1].Value

$setupName = 'MaoJuan-v{0}-windows-setup.exe' -f $version
$portableName = 'MaoJuan-v{0}-windows-portable.zip' -f $version

Write-Host ("MaoJuan promo deploy - version v{0}, project '{1}'" -f $version, $Project)
Write-Host ''

# ---- 1. staging dir ------------------------------------------------------------
Write-Step 1 "staging into build/promo_deploy"
if (Test-Path $stageDir) {
    try {
        Remove-Item $stageDir -Recurse -Force -ErrorAction Stop
    } catch {
        throw ("cannot clear $stageDir - a process is holding it (a local preview server, " +
               "or File Explorer with that folder open). Close it and retry.")
    }
}
New-Item -ItemType Directory -Path (Join-Path $stageDir 'download') -Force | Out-Null

Copy-Item (Join-Path $promo 'index.html') $stageDir -Force
Copy-Item (Join-Path $promo '404.html') $stageDir -Force
Copy-Item (Join-Path $promo '.nojekyll') $stageDir -Force
Copy-Item (Join-Path $promo 'assets') $stageDir -Recurse -Force

# ---- 2. Windows installers (ASCII names) ---------------------------------------
Write-Step 2 "copying Windows installers from dist/"

function Copy-Newest($pattern, $destName) {
    if (-not (Test-Path $dist)) { return $false }
    $f = Get-ChildItem -Path $dist -Filter $pattern -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { return $false }
    Copy-Item $f.FullName (Join-Path $stageDir ('download\' + $destName)) -Force
    Write-Host ("      {0}  <-  {1} ({2:N1} MB)" -f $destName, $f.Name, ($f.Length / 1MB))
    return $true
}

# 1.28.0 installers are 'MaoJuan...' on the release but Chinese-named locally.
$gotSetup = Copy-Newest ('*Setup-{0}-Windows-x64.exe' -f $version) $setupName
$gotPortable = Copy-Newest ('*Windows-*.zip' -f $version) $portableName

# Android: arm64 build is ~20MB so it fits the 25MiB Pages limit; the universal
# build (~35MB) does not and is served from Releases instead (see deploy_pages.ps1).
$apkArm64Name = 'MaoJuan-v{0}-android-arm64.apk' -f $version
$gotApk = Copy-Newest ('MaoJuan-v{0}-android-arm64.apk' -f $version) $apkArm64Name
if (-not $gotApk) {
    Write-Warning ("no arm64 APK found in dist/ ({0}); the Android button will fall back to Releases" -f $apkArm64Name)
}

if (-not $gotSetup) {
    Write-Warning ("no Windows setup exe found in dist/ matching '*Setup-{0}-Windows-x64.exe'" -f $version)
}
if (-not $gotPortable) {
    Write-Warning "no portable zip found in dist/ - the 'Windows green build' button will 404 until you build it"
}

# ---- 3. size guard -------------------------------------------------------------
Write-Step 3 "checking file sizes against the 25 MiB Pages limit"
$tooBig = @()
Get-ChildItem $stageDir -Recurse -File | ForEach-Object {
    if ($_.Length -gt $LIMIT) { $tooBig += $_ }
}
if ($tooBig.Count -gt 0) {
    Write-Host '      OVER LIMIT:' -ForegroundColor Red
    foreach ($f in $tooBig) {
        Write-Host ("        {0:N1} MB  {1}" -f ($f.Length / 1MB), $f.FullName.Replace($stageDir, '')) -ForegroundColor Red
    }
    if (-not $NoSizeCheck) {
        throw "one or more files exceed the 25 MiB per-file limit; move them to a netdisk / R2 instead"
    }
} else {
    $total = (Get-ChildItem $stageDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Write-Host ("      OK - {0} files, {1:N1} MB total" -f (Get-ChildItem $stageDir -Recurse -File).Count, ($total / 1MB))
}

if ($Stage) {
    Write-Host ''
    Write-Host "Staged at: $stageDir" -ForegroundColor Green
    Write-Host 'Dashboard upload: Cloudflare Pages > your project > Create deployment > drag this folder.'
    exit 0
}

# ---- 4. upload ------------------------------------------------------------------
Write-Step 4 "uploading with wrangler"

if (-not $env:CLOUDFLARE_API_TOKEN) {
    Write-Host ''
    Write-Host 'CLOUDFLARE_API_TOKEN is not set.' -ForegroundColor Yellow
    Write-Host 'Set it first, then re-run:'
    Write-Host '  $env:CLOUDFLARE_API_TOKEN  = "<your token>"'
    Write-Host '  $env:CLOUDFLARE_ACCOUNT_ID = "<your account id>"'
    Write-Host ''
    Write-Host "Or use -Stage and drag build/promo_deploy into the Cloudflare dashboard." -ForegroundColor Yellow
    exit 1
}

$wrangler = Get-Command wrangler -ErrorAction SilentlyContinue
if (-not $wrangler) {
    Write-Host '      wrangler not found, installing...'
    npm install -g wrangler --registry=https://registry.npmmirror.com
    if ($LASTEXITCODE -ne 0) { throw 'npm install -g wrangler failed' }
}

Push-Location $stageDir
try {
    & wrangler pages deploy . --project-name=$Project --branch=$Branch --commit-dirty=true
    if ($LASTEXITCODE -ne 0) { throw "wrangler pages deploy failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

Write-Host ''
Write-Host ("Deployed. https://{0}.pages.dev" -f $Project) -ForegroundColor Green
