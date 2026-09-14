# MaoJuan - one-command release: build, verify, publish, deploy
#
# Full chain, in order:
#   1. flutter analyze            (0 error / 0 warning; info-level lints are fine)
#   2. flutter test               (must be all green)
#   3. build Windows + universal APK
#   4. verify_reference           (must print >>> PASS)
#   5. signature check            (must be 43a9e0a1...)
#   6. build arm64 APK + stage all artifacts with ASCII names + sha256
#   7. create/update the GitHub Release and upload the assets
#   8. deploy the promo site to GitHub Pages (tools\deploy_pages.ps1)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\publish_release.ps1
#   ... -Version 1.29.0   # 可不传：默认取 pubspec.yaml；传了则必须与之一致
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
# 版本号约定：pubspec.yaml 的 version 字段是**唯一来源**。App 内展示的版本号
# 由下面的 $appVersionDefine 通过 --dart-define 注入（见 lib/utils/app_constants.dart），
# 因此不需要在任何 Dart 文件里手工改版本号。
param(
    [string]$Version = '',
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

# ---- 版本号单一来源（pubspec.yaml）+ 一致性闸门 --------------------------------
# 为什么不直接信任 -Version 参数：v1.28.0 曾发生「APK versionName 误标」事故，
# 根因就是版本号有多处手工来源。现在 pubspec.yaml 是唯一来源：
#   · 不传 -Version  → 取 pubspec
#   · 传了 -Version  → 必须与 pubspec 一致，否则终止发布
#   · App 内展示的版本号由 $appVersionDefine 注入，无第二处手工填写
$pubLine = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:' |
    Select-Object -First 1
if (-not $pubLine) { Fail 'pubspec.yaml 缺少 version: 字段' }
$pubVersion = $pubLine.Line.Split(':')[-1].Trim()          # 形如 1.28.1+20
$pubParts = $pubVersion.Split('+')
$pubName = $pubParts[0]
$pubBuild = if ($pubParts.Length -gt 1) { $pubParts[1] } else { '0' }
if ($Version -eq '') {
    $Version = $pubName
    Write-Host ("version from pubspec.yaml: {0} (build {1})" -f $pubName, $pubBuild) -ForegroundColor DarkGray
} elseif ($Version -ne $pubName) {
    Fail ("version mismatch: -Version {0} != pubspec.yaml {1} —— 先改 pubspec.yaml（唯一来源）再发布" -f $Version, $pubName)
}
$appVersionDefine = 'APP_VERSION=v{0}.{1}' -f $pubName, $pubBuild

Set-Location $root
Write-Host ("MaoJuan release v{0}" -f $Version) -ForegroundColor Green

$apkArm64Name = 'MaoJuan-v{0}-android-arm64.apk' -f $Version
$apkUnivName = 'MaoJuan-v{0}-android-universal.apk' -f $Version
$setupName = 'MaoJuan-v{0}-windows-setup.exe' -f $Version
$portableName = 'MaoJuan-v{0}-windows-portable.zip' -f $Version

# ---- 1/2. analyze + test -------------------------------------------------------
if (-not $SkipTests) {
    Step '1/8' 'flutter analyze'
    # 用文件重定向而非 PS 管道：flutter/dart 在管道模式下可能长时间阻塞
    cmd /c "flutter analyze > build\_analyze.txt 2>&1"
    $analyzeOut = Get-Content (Join-Path $root 'build\_analyze.txt')
    # 门槛 = 0 error / 0 warning；info 为既有风格噪音不算失败
    # （flutter analyze 对任何 issue 都返回非零退出码，不能只看退出码）
    $bad = @($analyzeOut | Where-Object { $_ -match '^\s+(error|warning) ' })
    if ($bad.Count -gt 0) {
        $bad | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" }
        Fail ("flutter analyze: {0} error/warning" -f $bad.Count)
    }
    $info = @($analyzeOut | Where-Object { $_ -match '^\s+info ' }).Count
    Write-Host ("    0 error / 0 warning / {0} info（既有风格噪音）" -f $info)

    Step '2/8' 'flutter test'
    & flutter test
    if ($LASTEXITCODE -ne 0) { Fail 'flutter test failed' }
} else {
    Write-Host 'skipping analyze/test (-SkipTests)'
}

# ---- 3. build Windows + universal APK ------------------------------------------
Step '3/8' 'building Windows + universal APK'
$env:JAVA_HOME = 'D:\dev\jdk21'
& flutter build apk --release --obfuscate --split-debug-info=build/symbols --dart-define=$appVersionDefine
if ($LASTEXITCODE -ne 0) { Fail 'universal APK build failed' }
& flutter build windows --release --dart-define=$appVersionDefine
if ($LASTEXITCODE -ne 0) { Fail 'Windows build failed' }

$universalSrc = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $universalSrc)) { Fail "APK not found: $universalSrc" }

# ---- 4. reference gate ---------------------------------------------------------
Step '4/8' 'verify_reference (four-dimension baseline)'
# 直接调用 .bat（不经过 cmd /c：嵌套引号会被 cmd 二次拆分，中文注释行会被误当命令）
$bat = Join-Path $root 'tools\reference_check\verify_reference.bat'
if (-not (Test-Path $bat)) { Fail "verify_reference.bat not found: $bat" }
$out = & $bat $universalSrc 2>&1
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
# keytool 输出形如 SHA256: 43:A9:...（冒号分隔），比对前先去掉冒号与空白
$certHex = ($line -replace '[:\s]', '')
if ($certHex -notmatch $EXPECTED_CERT) { Fail "signing cert mismatch: expected $EXPECTED_CERT..." }

# ---- 6. build arm64 + stage all artifacts --------------------------------------
Step '6/8' 'building arm64 APK and staging artifacts'

# 先把通用版落盘（arm64 构建会覆盖 build/.../app-release.apk）
$apkUnivDst = Join-Path $dist $apkUnivName
Copy-Item $universalSrc $apkUnivDst -Force; SaveHash $apkUnivDst

& flutter build apk --release --obfuscate --split-debug-info=build/symbols --target-platform android-arm64 --dart-define=$appVersionDefine
if ($LASTEXITCODE -ne 0) { Fail 'arm64 APK build failed' }
$arm64Src = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
$apkArm64Dst = Join-Path $dist $apkArm64Name
Copy-Item $arm64Src $apkArm64Dst -Force; SaveHash $apkArm64Dst

# Windows installers: package portable zip, then compile the setup with the
# version and the **actual** package dir passed in (see maojuan_setup.iss header:
# SrcDir used to be hard-coded to a stale date, which could pack old content).
$pkgDir = Join-Path $dist ("猫卷-Windows-{0}" -f (Get-Date -Format 'yyyyMMdd'))
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'package_windows.ps1') -PkgDir $pkgDir | Out-Null
if (-not (Test-Path $pkgDir)) { Fail "portable package dir not produced: $pkgDir" }
$iss = Join-Path $PSScriptRoot 'maojuan_setup.iss'
& 'C:\Users\CTSwe\AppData\Local\Programs\Inno Setup 6\ISCC.exe' "/DMyAppVersion=$Version" "/DSrcDir=$pkgDir" $iss | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'Inno Setup compile failed' }

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

# ---- 6.5 sync promo page (sha256 + version) -------------------------------------
# 推广页 window.MAOJUAN 里的 sha256 与版本号必须与本次产物一致，否则页面展示
# 过期校验值 / 下载 404。这里按 dist 里的四个产物就地改写 promo/index.html
# （无 BOM，保持原样），版本号也一并同步——避免「改了 pubspec 忘了改推广页」。
$promo = Join-Path $root 'promo\index.html'
$promoText = [System.IO.File]::ReadAllText($promo, [System.Text.Encoding]::UTF8)
$promoHashes = @{
    apk      = Hash $apkArm64Dst
    apkUniv  = Hash $apkUnivDst
    setup    = Hash $setupDst
    portable = Hash $portableDst
}
foreach ($k in $promoHashes.Keys) {
    # 注意：不能用 -f 拼这个正则——{64} 会被 -f 当占位符。三组：前缀 / 旧哈希 / 闭引号，
    # 替换串用 ${1}/${3}（花括号形式，防止哈希以数字开头被解析成分组引用）。
    $pattern = '(\b' + $k + '\s*:\s*")([0-9a-fA-F]{64})(")'
    $promoText = [regex]::Replace($promoText, $pattern,
        ('${1}' + $promoHashes[$k] + '${3}'))
}
# version / buildDate 与四个同源下载文件名（download/MaoJuan-v<版本>-...）
$promoText = [regex]::Replace($promoText, '(version:\s*")[^"]+(")',
    ('${1}' + $Version + '${2}'))
$promoText = [regex]::Replace($promoText, '(buildDate:\s*")[^"]+(")',
    ('${1}' + (Get-Date -Format 'yyyyMMdd') + '${2}'))
$promoText = [regex]::Replace($promoText, '(download/MaoJuan-)v[\d.]+(-android-)',
    ('${1}v' + $Version + '${2}'))
$promoText = [regex]::Replace($promoText, '(download/MaoJuan-)v[\d.]+(-windows-)',
    ('${1}v' + $Version + '${2}'))
[System.IO.File]::WriteAllText($promo, $promoText, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("    promo/index.html synced to v{0} (sha256 + version + download names)" -f $Version)

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
    # 传给第 8 步的 deploy_pages.ps1 子进程：非 TTY 下 GCM 选择器会挂死 git push，
    # 部署脚本检测到 GH_TOKEN 会改用 Basic 认证头推送
    $env:GH_TOKEN = $token

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
    # 注意：URL 必须用 -f 拼接。"$var?name=..." 会被 PowerShell 把 $var? 解析成
    # 一个不存在的变量（? 属于变量名字符集），得到残缺 URL，curl 静默失败。
    $upFile = Join-Path $root 'build\_up.json'
    foreach ($a in $assets) {
        Write-Host ("    uploading {0} ({1:N1} MB)" -f $a.name, ((Get-Item $a.path).Length / 1MB))
        $upUrl = '{0}?name={1}' -f $uploadBase, $a.name
        curl.exe -sS -o $upFile -X POST `
            -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' `
            -H 'Content-Type: application/octet-stream' `
            --data-binary "@$($a.path)" $upUrl 2>&1
        $curlCode = $LASTEXITCODE
        if ($curlCode -ne 0 -or -not (Test-Path $upFile)) {
            Fail ("asset upload failed (curl exit {0}): {1}" -f $curlCode, $a.name)
        }
        $up = Get-Content $upFile -Raw | ConvertFrom-Json
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
