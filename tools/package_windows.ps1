# 猫卷 Windows 桌面版打包脚本
# 前置：flutter build windows --release 已成功
# 产物：dist\猫卷-Windows-<日期>\（绿色版目录） + dist\猫卷-Windows-<日期>.zip
#
# 参数：
#   -PkgDir <路径>  指定绿色版输出目录（默认 dist\猫卷-Windows-<yyyyMMdd>）。
#                   publish_release.ps1 会显式传入，好让安装包脚本（.iss）的
#                   SrcDir 与实际产物目录**由构造保证一致**——此前 .iss 里的
#                   SrcDir 写死了一个日期，且没人更新它，存在打包进旧内容的风险。
param(
    [string]$PkgDir = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$buildDir = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path $buildDir)) {
    Write-Host '未找到构建产物，请先执行：flutter build windows --release' -ForegroundColor Red
    exit 1
}

$distRoot = Join-Path $root 'dist'
$stamp = Get-Date -Format 'yyyyMMdd'
$pkgName = "猫卷-Windows-$stamp"
$pkgDir = if ($PkgDir) { $PkgDir } else { Join-Path $distRoot $pkgName }
if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
New-Item -ItemType Directory -Path $pkgDir | Out-Null

Copy-Item "$buildDir\*" $pkgDir -Recurse

# 额外生成中文名启动器（同目录依赖不受影响）
Copy-Item "$pkgDir\flashcard_app.exe" "$pkgDir\猫卷.exe"

# AGPL-3.0 要求随二进制分发协议文本（命名为 .txt 便于 Windows 用户直接打开）
Copy-Item (Join-Path $root 'LICENSE') "$pkgDir\LICENSE.txt"

# 使用说明
@'
猫卷 · Windows 桌面版
====================

运行：双击 猫卷.exe（或 flashcard_app.exe）即可，无需安装。

说明：
- 数据保存在 %LOCALAPPDATA%\flashcard_app\flashcard.db（SQLite 数据库）
- 首次启动若被 SmartScreen 提示"未识别的应用"，点「更多信息 → 仍要运行」即可（未做代码签名）
- 手写批注：刷题页右上角画笔按钮进入；鼠标按住左键即可书写
'@ | Out-File "$pkgDir\使用说明.txt" -Encoding UTF8

$zipPath = Join-Path $distRoot "$(Split-Path $pkgDir -Leaf).zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$pkgDir\*" -DestinationPath $zipPath -CompressionLevel Optimal

Write-Output "打包完成："
Write-Output "  目录：$pkgDir"
Write-Output "  压缩：$zipPath ($([math]::Round((Get-Item $zipPath).Length/1MB,1)) MB)"
