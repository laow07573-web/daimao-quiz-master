# MaoJuan - sync the current working tree (master HEAD) onto origin/main
#
# The repo has two lines by design:
#   master      full local development history (detailed commits, never pushed)
#   main        the public line on GitHub (June history + squashed milestones)
#
# This script publishes the CURRENT WORKING TREE of master to origin/main as a
# single commit on top of the remote tip - non-destructive fast-forward, the
# June history stays intact, and nothing enters the remote that is not on disk.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\sync_main.ps1 [-Message "..."]
#
param(
    [string]$Message = 'sync: 同步 master 工作树到 main'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$gitDir = Join-Path $root '.git'

Set-Location $root

# ---- git over HTTPS：失效代理自动改直连 ------------------------------------------
# 本机/仓库里可能配着 http.https://github.com.proxy 指向本地代理（实测 127.0.0.1:7897）；
# 代理进程没起来时，fetch/push 会直接失败（04 踩坑手册第 10 条）。
# 先用现有配置执行一次，失败再清空代理直连重试——只作用于本次调用，不动用户全局配置。
function Invoke-GitProxyAware {
    param([string[]]$GitArgs)
    & git @GitArgs
    if ($LASTEXITCODE -eq 0) { return }
    Write-Host '  git 失败：配置的代理可能不可用，改用直连重试…' -ForegroundColor Yellow
    & git -c 'http.https://github.com.proxy=' -c 'https.proxy=' @GitArgs
    if ($LASTEXITCODE -ne 0) { throw ('git failed: git ' + ($GitArgs -join ' ')) }
}

# fetch remote tip first (needs proxy in CN; HTTPS_PROXY env is honoured)
Invoke-GitProxyAware @('fetch', 'origin', 'main')

$remoteTip = (& git rev-parse refs/remotes/origin/main).Trim()
$tree = (& git rev-parse 'HEAD^{tree}').Trim()
Write-Host ("remote tip : {0}" -f $remoteTip)
Write-Host ("tree to pub: {0}" -f $tree)

# tree identical to remote tip -> nothing to do
if ($tree -eq (& git rev-parse ("{0}^{{tree}}" -f $remoteTip)).Trim()) {
    Write-Host 'already in sync - nothing to push.' -ForegroundColor Green
    exit 0
}

$saved = @{}
foreach ($k in 'GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL') {
    $saved[$k] = (Get-Item "Env:\$k" -ErrorAction SilentlyContinue).Value
}
$env:GIT_AUTHOR_NAME = '笨蛋鱼坏蛋猫'; $env:GIT_AUTHOR_EMAIL = 'laow07573@gmail.com'
$env:GIT_COMMITTER_NAME = $env:GIT_AUTHOR_NAME; $env:GIT_COMMITTER_EMAIL = $env:GIT_AUTHOR_EMAIL
try {
    $commit = (& git commit-tree $tree -p $remoteTip -m $Message).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $commit) { throw 'commit-tree failed' }
} finally {
    foreach ($k in $saved.Keys) {
        if ($saved[$k]) { Set-Item "Env:\$k" $saved[$k] } else { Remove-Item "Env:\$k" -ErrorAction SilentlyContinue }
    }
}
& git branch -f main $commit | Out-Null
Write-Host ("commit     : {0}" -f $commit)

Invoke-GitProxyAware @(
    '-c', 'credential.helper=',
    '-c', 'credential.helper=D:/dev/git/mingw64/bin/git-credential-manager.exe',
    'push', 'origin', 'main', '--force-with-lease')

Write-Host ''
Write-Host 'main synced. https://github.com/laow07573-web/daimao-quiz-master' -ForegroundColor Green
