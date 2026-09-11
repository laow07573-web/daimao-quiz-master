# 猫卷 Windows 桌面版打包脚本
# 前置：flutter build windows --release 已成功
# 产物：dist\猫卷-Windows-<日期>\（绿色版目录） + dist\猫卷-Windows-<日期>.zip
$ErrorActionPreference = 'Stop'

$buildDir = 'd:\dev\flashcard_app\build\windows\x64\runner\Release'
if (-not (Test-Path $buildDir)) {
    Write-Host '未找到构建产物，请先执行：flutter build windows --release' -ForegroundColor Red
    exit 1
}

$stamp = Get-Date -Format 'yyyyMMdd'
$distRoot = 'd:\dev\flashcard_app\dist'
$pkgName = "猫卷-Windows-$stamp"
$pkgDir = Join-Path $distRoot $pkgName
if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
New-Item -ItemType Directory -Path $pkgDir | Out-Null

Copy-Item "$buildDir\*" $pkgDir -Recurse

# 额外生成中文名启动器（同目录依赖不受影响）
Copy-Item "$pkgDir\flashcard_app.exe" "$pkgDir\猫卷.exe"

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

$zipPath = Join-Path $distRoot "$pkgName.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$pkgDir\*" -DestinationPath $zipPath -CompressionLevel Optimal

Write-Output "打包完成："
Write-Output "  目录：$pkgDir"
Write-Output "  压缩：$zipPath ($([math]::Round((Get-Item $zipPath).Length/1MB,1)) MB)"
