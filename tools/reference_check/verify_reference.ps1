# 猫卷 · 基线对照验证（后续每次更新打包后必跑）
# 用法: powershell -ExecutionPolicy Bypass -File verify_reference.ps1 [APK路径]
# 默认取 dist\ 下最新 apk；对照基准: ..\..\reference\
param([string]$ApkPath = '')

$ErrorActionPreference = 'Continue'
# 项目根 = 本脚本（tools\reference_check\）上三级
$ROOT = (Resolve-Path (Join-Path (Split-Path -Parent $PSCommandPath) '..\..')).Path
$REF   = Join-Path $ROOT 'reference'
$DART  = 'D:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe'
$JAVA  = 'D:\dev\jdk21\bin\java.exe'
$SDK   = 'D:\dev\Android\Sdk'
$APKANALYZER_JAR = Join-Path $SDK 'cmdline-tools\latest\lib\apkanalyzer-classpath.jar'
$WORK  = Join-Path $env:TEMP ("refcheck_" + [System.IO.Path]::GetRandomFileName())

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $dist = Join-Path $ROOT 'dist'
    $ApkPath = Get-ChildItem -Path $dist -Filter '*.apk' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $ApkPath) { Write-Output '[ERROR] 未找到 APK'; exit 1 }
}

Write-Output ('[1/5] 解包: ' + $ApkPath)
New-Item -ItemType Directory -Force -Path (Join-Path $WORK 'apk') | Out-Null
Copy-Item $ApkPath (Join-Path $WORK 'a.zip') -Force
Expand-Archive (Join-Path $WORK 'a.zip') (Join-Path $WORK 'apk') -Force

Write-Output '[2/5] 提取 manifest'
& $JAVA "-Dcom.android.sdklib.toolsdir=$SDK\cmdline-tools\latest" `
    -classpath $APKANALYZER_JAR com.android.tools.apk.analyzer.ApkAnalyzerCli `
    manifest print $ApkPath 2>$null |
    Set-Content -Encoding utf8 (Join-Path $WORK 'manifest.xml')

Write-Output '[3/5] 提取 libapp.so 中文文案'
$so = Join-Path $WORK 'apk\lib\arm64-v8a\libapp.so'
if (-not (Test-Path $so)) { Write-Output '[ERROR] 未找到 arm64 libapp.so'; exit 1 }
& $DART (Join-Path $ROOT 'tools\reference_check\extract_strings.dart') $so (Join-Path $WORK 'strings.txt') | Out-Null

Write-Output '[4/5] 提取 assets 清单'
Get-ChildItem -Recurse (Join-Path $WORK 'apk\assets\flutter_assets\assets') -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Name } | Sort-Object |
    Set-Content -Encoding ascii (Join-Path $WORK 'assets.txt')

Write-Output '[5/5] 四维对照'
& $DART (Join-Path $ROOT 'tools\reference_check\check.dart') `
    (Join-Path $WORK 'manifest.xml') `
    (Join-Path $WORK 'strings.txt') `
    (Join-Path $WORK 'assets.txt')

Remove-Item -Recurse -Force $WORK -ErrorAction SilentlyContinue





