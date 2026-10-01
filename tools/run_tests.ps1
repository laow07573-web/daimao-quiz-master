# MaoJuan - 一键跑「静态分析 + 全量测试」，数据目录一次性隔离
#
# 为什么必须隔离（踩过的坑）：
#   测试库落在 %LOCALAPPDATA%\flashcard_app\ 下，多个测试文件共用该目录。
#   一旦目录里留着「跨 schema 代际」的旧库，本轮就会大面积假红：
#   onCreate 不再触发 → 补建索引时报 no such table: main.question_images，
#   并发测试还会互相 database is locked（实测 392 项里挂了 190 项）。
#   本脚本为每次运行分配一个全新的临时 LOCALAPPDATA，跑完即删：
#   既不会被旧库污染，也绝不会碰到你本机 App 的真实数据目录。
#
# 判定标准（与 CI 一致）：analyze 0 error / 0 warning；test 全绿。
# 退出码显式取自各命令，不经管道（管道会吃掉真实退出码，见 04 手册第 2 条）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
#   ... -AnalyzeOnly    # 只跑分析
#   ... -Keep           # 保留本次临时目录（排查用）

param(
    [switch]$AnalyzeOnly,
    [switch]$Keep
)

# 原生命令的 stderr（flutter 的横幅提示）在 EAP=Stop 下会被当终止错误，
# 因此这里按退出码判定成败 —— 与 tools\deploy_pages.ps1 同一处理
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

$envDir = Join-Path ([System.IO.Path]::GetTempPath()) ('mj_test_env_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $envDir -Force | Out-Null
$saved = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $envDir
Write-Host ("test data dir : {0}" -f $envDir) -ForegroundColor Cyan

$failed = @()
try {
    Write-Host ''
    Write-Host '=== flutter analyze --no-fatal-infos ===' -ForegroundColor Cyan
    & flutter analyze --no-fatal-infos
    if ($LASTEXITCODE -ne 0) { $failed += ('analyze exit ' + $LASTEXITCODE) }

    if (-not $AnalyzeOnly) {
        Write-Host ''
        Write-Host '=== flutter test ===' -ForegroundColor Cyan
        & flutter test
        if ($LASTEXITCODE -ne 0) { $failed += ('test exit ' + $LASTEXITCODE) }
    }
} finally {
    if ($saved) { $env:LOCALAPPDATA = $saved } else { Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue }
    if ($Keep) {
        Write-Host ("kept test data dir : {0}" -f $envDir) -ForegroundColor Yellow
    } else {
        Remove-Item $envDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ('FAILED: ' + ($failed -join '; ')) -ForegroundColor Red
    exit 1
}
Write-Host 'OK: analyze 0 error / 0 warning；测试全绿' -ForegroundColor Green
exit 0
