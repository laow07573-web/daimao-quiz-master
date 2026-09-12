# MaoJuan - publish the promo site to GitHub Pages (branch: gh-pages)
#
# GitHub Pages is the zero-signup host: it only needs the GitHub account we
# already push to. Its weakness is mainland reachability, so
# tools\deploy_promo.ps1 (Cloudflare Pages) is the preferred host once set up -
# both read the same window.MAOJUAN config block, so switching is a one-liner.
#
# This script:
#   1. stages a clean copy of promo/ into build/gh_pages
#   2. ships the installers into download/ (Pages allows 100MB/file, so the
#      20.4MB arm64 APK, the 34.7MB universal APK and both Windows packages all
#      download same-origin - no netdisk needed)
#   3. commits to the orphan gh-pages branch WITHOUT touching your working tree
#   4. force-with-lease pushes it
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\deploy_pages.ps1
#   ... -DryRun        # stage + build the commit, but do not push
#
param(
    [string]$Repo = 'origin',
    [string]$ReleaseTag = '',   # default: v<version> read from index.html
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$promo = Join-Path $root 'promo'
$stage = Join-Path $root 'build\gh_pages'
$gitDir = Join-Path $root '.git'
$owner = 'laow07573-web'
$repoName = 'daimao-quiz-master'

function Step($n, $m) { Write-Host ''; Write-Host ("=== [{0}] {1}" -f $n, $m) -ForegroundColor Cyan }
function Utf8NoBom($p, $text) {
    [System.IO.File]::WriteAllText($p, $text, (New-Object System.Text.UTF8Encoding($false)))
}

Set-Location $root
$idx = Join-Path $promo 'index.html'
if (-not (Test-Path $idx)) { throw 'promo/index.html not found' }
$html = [System.IO.File]::ReadAllText($idx, [System.Text.Encoding]::UTF8)
$verMatch = [regex]::Match($html, 'version:\s*"([0-9.]+)"')
if (-not $verMatch.Success) { throw 'cannot read version from window.MAOJUAN' }
$version = $verMatch.Groups[1].Value
if (-not $ReleaseTag) { $ReleaseTag = 'v' + $version }

Write-Host ("MaoJuan Pages deploy - v{0}, assets from {1}" -f $version, $ReleaseTag) -ForegroundColor Green

# ---- 1. stage ------------------------------------------------------------------
Step '1/4' 'staging into build/gh_pages'
if (Test-Path $stage) {
    try { Remove-Item $stage -Recurse -Force -ErrorAction Stop }
    catch { throw "cannot clear $stage - close any preview server or Explorer window on it, then retry" }
}
New-Item -ItemType Directory -Path (Join-Path $stage 'assets')   -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'download') -Force | Out-Null
Copy-Item (Join-Path $promo 'index.html') $stage -Force
# promo/demo.html 是本地录屏专用文件（file:// 直开），不上架网站
Copy-Item (Join-Path $promo '404.html')   $stage -Force
Copy-Item (Join-Path $promo '.nojekyll')  $stage -Force
Copy-Item (Join-Path $promo 'assets\logo.png') (Join-Path $stage 'assets') -Force

# Ship the installers alongside the page: GitHub Pages allows up to 100MB per
# file (unlike Cloudflare Pages' 25MB), so all four fit and download same-origin.
$dist = Join-Path $root 'dist'
function Copy-Artifact([string]$srcName, [string]$destName) {
    $src = Join-Path $dist $srcName
    if (-not (Test-Path $src)) { Write-Warning "missing in dist/: $srcName"; return $false }
    Copy-Item $src (Join-Path $stage ('download\' + $destName)) -Force
    Write-Host ("    {0}  ({1:N1} MB)" -f $destName, ((Get-Item $src).Length / 1MB))
    return $true
}
Write-Host '    copying installers into download/:'
$null = Copy-Artifact ('MaoJuan-v{0}-android-arm64.apk'     -f $version) ('MaoJuan-v{0}-android-arm64.apk'     -f $version)
$null = Copy-Artifact ('MaoJuan-v{0}-android-universal.apk' -f $version) ('MaoJuan-v{0}-android-universal.apk' -f $version)
$null = Copy-Artifact ('MaoJuan-v{0}-windows-setup.exe'     -f $version) ('MaoJuan-v{0}-windows-setup.exe'     -f $version)
$null = Copy-Artifact ('MaoJuan-v{0}-windows-portable.zip'  -f $version) ('MaoJuan-v{0}-windows-portable.zip'  -f $version)

# ---- 2. verify config points at files that were actually staged ---------------
Step '2/4' 'checking the window.MAOJUAN download paths'
$f = Join-Path $stage 'index.html'
$s = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)

# Downloads stay same-origin (download/...) - the files ship in this branch.
# Only sanity-check that every configured download/ path actually exists.
foreach ($key in 'android','androidUniversal','windowsSetup','windowsPortable') {
    $m = [regex]::Match($s, ('\b' + $key + '\s*:\s*"(download/[^"]+)"'))
    if ($m.Success) {
        $rel = $m.Groups[1].Value.Replace('/', '\')
        if (-not (Test-Path (Join-Path $stage $rel))) { throw ("config points at a missing file: " + $m.Groups[1].Value) }
        Write-Host ("    {0,-17} -> {1}" -f $key, $m.Groups[1].Value)
    } else {
        Write-Host ("    {0,-17} -> (non-download URL, left as-is)" -f $key)
    }
}
Utf8NoBom $f $s

# 404 references favicon.png which does not exist - point it at the logo
$f404 = Join-Path $stage '404.html'
Utf8NoBom $f404 ([System.IO.File]::ReadAllText($f404, [System.Text.Encoding]::UTF8).Replace('href="favicon.png"', 'href="assets/logo.png"'))

# ---- 3. commit to gh-pages via a temp index (working tree untouched) -----------
Step '3/4' 'committing to the gh-pages branch'
$tmpIdx = Join-Path $root 'build\_ghpages_index'
if (Test-Path $tmpIdx) { Remove-Item $tmpIdx -Force }
$env:GIT_INDEX_FILE = $tmpIdx
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'      # git writes warnings to stderr; judge by exit code
Push-Location $stage
try {
    & git --git-dir="$gitDir" --work-tree=. add -A . 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
    $tree = (& git --git-dir="$gitDir" write-tree 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $tree) { throw 'git write-tree failed' }
} finally {
    Pop-Location
    $ErrorActionPreference = $prevEap
    Remove-Item Env:\GIT_INDEX_FILE -ErrorAction SilentlyContinue
    if (Test-Path $tmpIdx) { Remove-Item $tmpIdx -Force }
}
Write-Host "    tree = $tree"

$saved = @{}
foreach ($k in 'GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL') {
    $saved[$k] = (Get-Item "Env:\$k" -ErrorAction SilentlyContinue).Value
}
$env:GIT_AUTHOR_NAME = '笨蛋鱼坏蛋猫'; $env:GIT_AUTHOR_EMAIL = 'laow07573@gmail.com'
$env:GIT_COMMITTER_NAME = $env:GIT_AUTHOR_NAME; $env:GIT_COMMITTER_EMAIL = $env:GIT_AUTHOR_EMAIL
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $msg = 'site: 推广页 v{0}（下载指向 Releases）' -f $version
    $commit = (& git --git-dir="$gitDir" commit-tree $tree -m $msg 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $commit) { throw 'git commit-tree failed' }
} finally {
    $ErrorActionPreference = $prevEap
    foreach ($k in $saved.Keys) {
        if ($saved[$k]) { Set-Item "Env:\$k" $saved[$k] } else { Remove-Item "Env:\$k" -ErrorAction SilentlyContinue }
    }
}
& git branch -f gh-pages $commit | Out-Null
Write-Host "    commit = $commit"

# ---- 4. push -------------------------------------------------------------------
if ($DryRun) {
    Step '4/4' 'dry run - not pushing'
    Write-Host "    staged at $stage, commit $commit on local gh-pages"
    exit 0
}
Step '4/4' 'pushing gh-pages'
# 非 TTY 环境下 GCM 的账号选择器会无声挂死推送（实测）。设置 GH_TOKEN 时改用
# Basic 认证头推送，完全绕开凭据助手；未设置则走原路径（前台交互可用）。
if ($env:GH_TOKEN) {
    $basic = [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes(('laow07573-web:{0}' -f $env:GH_TOKEN)))
    & git -c "http.extraheader=Authorization: Basic $basic" `
        push $Repo gh-pages --force-with-lease --progress
    if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
} else {
    & git push $Repo gh-pages --force-with-lease --progress
    if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
}

Write-Host ''
Write-Host ("Live at: https://{0}.github.io/{1}/" -f $owner, $repoName) -ForegroundColor Green
Write-Host 'Pages rebuilds in about a minute; the URL stays the same on every deploy.'
