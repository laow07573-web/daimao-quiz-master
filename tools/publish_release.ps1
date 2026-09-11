# MaoJuan - one-command release: build, verify, publish, deploy
#
# Full chain, in order:
#   1. flutter analyze            (must be 0 issues)
#   2. flutter test               (must be all green)
#   3. build Windows + universal APK
#   4. verify_reference           (must print >>> PASS)
#   5. signature check            (must be 43a9e0a1...)
#   6. build arm64 APK + stage all artifacts with ASCII names + sha256
#   7. create/update the GitHub Release and upload the assets
#   8. deploy the promo site to GitHub Pages (tools\deploy_pages.ps1)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\publish_release.ps1 -Version 1.29.0
#   ... -Note '更新说明'   # text shown in the release notes
#   ... -SkipTests        # skip analyze/test (only if you just ran them)
#   ... -SkipGithub       # local build + deploy only
#   ... -SkipDeploy       # build + release only
#
# Auth for the GitHub step: reuses the credential stored by Git Credential
# Manager (the account you push with). No extra token needed. Alternatively
# set $env:GH_TOKEN to a PAT with Contents: Read/Write.
#
# Artifact layout produced (all under dist/, ASCII names only - GitHub and
# Cloudflare strip non-ASCII from filenames):
#   MaoJuan-v<Version>-android-arm64.apk      ~20 MB, recommended for phones
#   MaoJuan-v<Version>-android-universal.apk  ~35 MB, all CPU architectures
#   MaoJuan-v<Version>-windows-setup.exe      installer
#   MaoJuan-v<Version>-windows-portable.zip   portable zip
#
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Note = '',
    [switch]$SkipTests,
    [switch]$SkipGithub,
    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dist = Join-Path $root 'dist'
$REPO = 'laow07573-web/daimao-quiz-master'
$repoName = 'daimao-quiz-master'
$API = "https://api.github.com/repos/$REPO"
$EXPECTED_CERT = '43a9e0a1'   # prefix of the official signing cert SHA-256

function Step($n, $msg) { Write-Host ''; Write-Host ("=== [{0}] {1}" -f $n, $msg) -ForegroundColor Cyan }
function Fail($msg) { Write-Host $msg -ForegroundColor Red; throw $msg }
function Hash($p) { (Get-FileHash -Algorithm SHA256 $p).Hash.ToLower() }
function SaveHash($p) { (Hash $p) | Set-Content ($p + '.sha256') -Encoding ascii -NoNewline }

Set-Location $root
Write-Host ("MaoJuan release v{0}" -f $Version) -ForegroundColor Green

$apkArm64Name = 'MaoJuan-v{0}-android-arm64.apk' -f $Version
$apkUnivName = 'MaoJuan-v{0}-android-universal.apk' -f $Version
$setupName = 'MaoJuan-v{0}-windows-setup.exe' -f $Version
$portableName = 'MaoJuan-v{0}-windows-portable.zip' -f $Version

# ---- 1/2. analyze + test -------------------------------------------------------
if (-not $SkipTests) {
    Step '1/8' 'flutter analyze'
    & flutter analyze
    if ($LASTEXITCODE -ne 0) { Fail 'flutter analyze reported issues' }

    Step '2/8' 'flutter test'
    & flutter test
    if ($LASTEXITCODE -ne 0) { Fail 'flutter test failed' }
} else {
    Write-Host 'skipping analyze/test (-SkipTests)'
}

# ---- 3. build Windows + universal APK ------------------------------------------
Step '3/8' 'building Windows + universal APK'
$env:JAVA_HOME = 'D:\dev\jdk21'
& flutter build apk --release --obfuscate --split-debug-info=build/symbols
if ($LASTEXITCODE -ne 0) { Fail 'universal APK build failed' }
& flutter build windows --release
if ($LASTEXITCODE -ne 0) { Fail 'Windows build failed' }

$universalSrc = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $universalSrc)) { Fail "APK not found: $universalSrc" }

# ---- 4. reference gate ---------------------------------------------------------
Step '4/8' 'verify_reference (four-dimension baseline)'
$out = & cmd /c "tools\reference_check\verify_reference.bat `"$universalSrc`"" 2>&1
$out | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" }
if (-not ($out -match 'PASS')) {
    Write-Host ''
    Write-Host 'If the only differences are reviewed new strings, merge the whitelist then re-run:' -ForegroundColor Yellow
    Write-Host '  $env:REFCHECK_MERGE=1; cmd /c "tools\reference_check\verify_reference.bat <apk>"' -ForegroundColor Yellow
    Fail 'verify_reference did not PASS'
}

# ---- 5. signature --------------------------------------------------------------
Step '5/8' 'signature check'
$certs = & 'D:\dev\jdk21\bin\keytool.exe' -printcert -jarfile $universalSrc 2>&1
$line = ($certs | Select-String -Pattern 'SHA256' | Select-Object -First 1).ToString()
Write-Host "    $line"
if ($line -notmatch $EXPECTED_CERT) { Fail "signing cert mismatch: expected $EXPECTED_CERT..." }

# ---- 6. build arm64 + stage all artifacts --------------------------------------
Step '6/8' 'building arm64 APK and staging artifacts'
& flutter build apk --release --obfuscate --split-debug-info=build/symbols --target-platform android-arm64
if ($LASTEXITCODE -ne 0) { Fail 'arm64 APK build failed' }
$arm64Src = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'

$apkArm64Dst = Join-Path $dist $apkArm64Name
Copy-Item $arm64Src $apkArm64Dst -Force; SaveHash $apkArm64Dst
$apkUnivDst = Join-Path $dist $apkUnivName
Copy-Item $universalSrc $apkUnivDst -Force; SaveHash $apkUnivDst

# Windows installers: package portable zip, bump the .iss version, compile setup
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'package_windows.ps1') | Out-Null
$iss = Join-Path $PSScriptRoot 'maojuan_setup.iss'
$issText = [System.IO.File]::ReadAllText($iss, [System.Text.Encoding]::UTF8)
$issText = $issText -replace 'MyAppVersion "[\d.]+"', ('MyAppVersion "{0}"' -f $Version)
[System.IO.File]::WriteAllText($iss, $issText, (New-Object System.Text.UTF8Encoding($true)))
& 'C:\Users\CTSwe\AppData\Local\Programs\Inno Setup 6\ISCC.exe' $iss | Out-Null

$setupSrc = Get-ChildItem $dist -Filter '*.windows-setup.exe' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setupSrc) {
    $setupSrc = Get-ChildItem $dist -Filter '猫卷-Setup-*-Windows-x64.exe' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if (-not $setupSrc) { Fail 'Windows setup exe not produced' }
$setupDst = Join-Path $dist $setupName
Copy-Item $setupSrc.FullName $setupDst -Force; SaveHash $setupDst

$zipSrc = Get-ChildItem $dist -Filter '猫卷-Windows-*.zip' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zipSrc) { Fail 'portable zip not produced' }
$portableDst = Join-Path $dist $portableName
Copy-Item $zipSrc.FullName $portableDst -Force; SaveHash $portableDst

foreach ($n in @($apkArm64Name, $apkUnivName, $setupName, $portableName)) {
    Write-Host ("    {0}  ({1:N1} MB)" -f $n, ((Get-Item (Join-Path $dist $n)).Length / 1MB))
}

# ---- 7. GitHub Release ---------------------------------------------------------
if (-not $SkipGithub) {
    Step '7/8' 'creating GitHub Release and uploading assets'

    # credential: GH_TOKEN env if set, otherwise Git Credential Manager
    $token = $env:GH_TOKEN
    if (-not $token) {
        $credInput = "protocol=https`nhost=github.com`n`n"
        $credOut = $credInput | & git credential fill 2>$null
        $token = ($credOut | Select-String '^password=').ToString().Substring(9)
    }
    if (-not $token) { Fail 'no GitHub credential (GH_TOKEN unset and GCM has none)' }

    $assets = @(
        @{ path = $apkArm64Dst;  name = $apkArm64Name },
        @{ path = $apkUnivDst;   name = $apkUnivName },
        @{ path = $setupDst;     name = $setupName },
        @{ path = $portableDst;  name = $portableName }
    )

    $bodyText = @"
## 猫卷 v$Version

$Note

### 下载

**Android（二选一）**

| 文件 | 大小 | 适用 |
|---|---|---|
| ``$apkArm64Name`` | 推荐 | 2017 年后绝大多数手机 |
| ``$apkUnivName`` | 通用 | 含全部 CPU 架构，不确定机型时用 |

**Windows**

| 文件 | 说明 |
|---|---|
| ``$setupName`` | Windows 10/11 64 位安装包 |
| ``$portableName`` | 绿色免安装，解压即用 |

### 校验值（SHA-256）

``````
$(($assets | ForEach-Object { '{0}  {1}' -f $_.name, (Hash $_.path) }) -join "`n")
``````
"@
    $bodyFile = Join-Path $root 'build\_release_body.md'
    New-Item -ItemType Directory -Path (Join-Path $root 'build') -Force | Out-Null
    [System.IO.File]::WriteAllText($bodyFile, $bodyText, (New-Object System.Text.UTF8Encoding($false)))

    # JSON via ConvertTo-Json (escapes CJK correctly)
    $payload = @{
        tag_name = "v$Version"
        name = "猫卷 v$Version"
        body = $bodyText
        prerelease = $false
        draft = $false
    } | ConvertTo-Json
    $jsonFile = Join-Path $root 'build\_release.json'
    [System.IO.File]::WriteAllText($jsonFile, $payload, (New-Object System.Text.UTF8Encoding($false)))

    # existing release?
    $tagApi = "$API/releases/tags/v$Version"
    curl.exe -s -o (Join-Path $root 'build\_rel.json') `
        -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' `
        -H 'User-Agent: maojuan-release' $tagApi
    $existing = $false
    try {
        $rel = Get-Content (Join-Path $root 'build\_rel.json') -Raw | ConvertFrom-Json
        if ($rel.id) { $existing = $true; $relId = $rel.id }
    } catch {}

    if ($existing) {
        Write-Host ("    release v$Version exists (id $relId) - updating notes and assets")
        curl.exe -s -o (Join-Path $root 'build\_rel.json') -X PATCH `
            -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' `
            -H 'Content-Type: application/json; charset=utf-8' `
            --data-binary "@$jsonFile" "$API/releases/$relId"
        # delete same-name assets, then re-upload (clobber)
        $assetsJson = Get-Content (Join-Path $root 'build\_rel.json') -Raw | ConvertFrom-Json
        foreach ($a in $assetsJson.assets) {
            if ($a.name -in @($apkArm64Name, $apkUnivName, $setupName, $portableName)) {
                curl.exe -s -X DELETE -H "Authorization: Bearer $token" `
                    -H 'Accept: application/vnd.github+json' -H 'User-Agent: maojuan-release' $a.url | Out-Null
            }
        }
    } else {
        curl.exe -s -o (Join-Path $root 'build\_rel.json') -X POST `
            -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' `
            -H 'Content-Type: application/json; charset=utf-8' `
            --data-binary "@$jsonFile" "$API/releases"
        $rel = Get-Content (Join-Path $root 'build\_rel.json') -Raw | ConvertFrom-Json
        if (-not $rel.id) { Fail ("release create failed: " + $rel.message) }
        $relId = $rel.id
    }

    $uploadBase = "https://uploads.github.com/repos/$REPO/releases/$relId/assets"
    foreach ($a in $assets) {
        Write-Host ("    uploading {0} ({1:N1} MB)" -f $a.name, ((Get-Item $a.path).Length / 1MB))
        curl.exe -s -o (Join-Path $root 'build\_up.json') -X POST `
            -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' `
            -H 'Content-Type: application/octet-stream' `
            --data-binary "@$($a.path)" "$uploadBase?name=$($a.name)"
        $up = Get-Content (Join-Path $root 'build\_up.json') -Raw | ConvertFrom-Json
        if (-not $up.state -or $up.state -ne 'uploaded') { Fail ("asset upload failed: " + $a.name) }
    }
    Write-Host ("    release: https://github.com/{0}/releases/tag/v{1}" -f $REPO, $Version)
} else {
    Write-Host 'skipping GitHub Release (-SkipGithub)'
}

# ---- 8. deploy the site --------------------------------------------------------
if (-not $SkipDeploy) {
    Step '8/8' 'deploying promo site to GitHub Pages'
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'deploy_pages.ps1')
    if ($LASTEXITCODE -ne 0) { Fail 'site deploy failed' }
} else {
    Write-Host 'skipping deploy (-SkipDeploy)'
}

Write-Host ''
Write-Host ("Done: v{0}" -f $Version) -ForegroundColor Green
Write-Host ("Site : https://laow07573-web.github.io/{0}/" -f $repoName) -ForegroundColor Green
