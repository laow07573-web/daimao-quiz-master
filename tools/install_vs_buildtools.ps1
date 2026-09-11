# 猫卷 Windows 桌面构建环境一键安装脚本
# 用途：安装 VS2022 Build Tools（C++ 桌面工作负载 + Windows 11 SDK），
#       满足 Flutter Windows 桌面编译的最小依赖。
# 用法：在【管理员】PowerShell 中执行：
#       powershell -ExecutionPolicy Bypass -File d:\dev\flashcard_app\tools\install_vs_buildtools.ps1
# 预计耗时：10~30 分钟（视网速），全程静默无需交互。

$ErrorActionPreference = 'Stop'

Write-Host '=== [1/3] 通过 winget 安装 Visual Studio BuildTools 2022（含 C++ 工具链 + Windows 11 SDK）===' -ForegroundColor Cyan
Write-Host '    安装位置：C:\VSBuildTools2022\BuildTools（无空格路径，避免参数解析问题）'
Write-Host '    组件缓存：D:\vs_buildtools_cache（D 盘，节省 C 盘空间）'

# 注意：override 值内不得含空格路径/嵌套引号，否则会被 winget 拆词；
# 缓存目录必须预先存在；VS 2022 缓存参数新语法为 --path cache=<dir>
#（旧版 --downloadCachePath 已被移除，传入会直接报 87）
New-Item -ItemType Directory -Force -Path 'D:\vs_buildtools_cache' | Out-Null

$override = @(
    '--quiet', '--wait', '--norestart',
    '--installPath', 'C:\VSBuildTools2022\BuildTools',
    '--path', 'cache=D:\vs_buildtools_cache',
    '--add', 'Microsoft.VisualStudio.Workload.VCTools',
    '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.22621',
    # flutter_secure_storage_windows / flutter_local_notifications_windows 需要 ATL 头文件，
    # VCTools 工作负载默认不含，必须显式添加（对应 VS IDE 中 C++ ATL 组件）
    '--add', 'Microsoft.VisualStudio.Component.VC.ATL',
    '--includeRecommended'
) -join ' '

# --force：包已安装时 winget 默认转升级流程（无新版则直接退出，不执行 override），
# 必须 --force 才会真正运行 setup 修改（加装组件）
winget install Microsoft.VisualStudio.2022.BuildTools `
    --accept-source-agreements --accept-package-agreements `
    --disable-interactivity --force --override $override

if ($LASTEXITCODE -ne 0) {
    Write-Host "winget 安装失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host '=== [2/3] 验证安装结果 ===' -ForegroundColor Cyan
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    & $vswhere -products * -property displayName
} else {
    Write-Host '未找到 vswhere，请检查安装日志' -ForegroundColor Yellow
}

Write-Host '=== [3/3] flutter doctor 复核 ===' -ForegroundColor Cyan
flutter doctor

Write-Host ''
Write-Host '完成！如 [X] Visual Studio 已变为 [√]，回到 Qoder 继续构建即可。' -ForegroundColor Green
