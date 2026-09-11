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

# fetch remote tip first (needs proxy in CN; HTTPS_PROXY env is honoured)
& git fetch origin main
if ($LASTEXITCODE -ne 0) { throw 'git fetch failed (set HTTPS_PROXY if github.com is unreachable)' }

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

& git -c credential.helper= `
      -c 'credential.helper=D:/dev/git/mingw64/bin/git-credential-manager.exe' `
      push origin main --force-with-lease
if ($LASTEXITCODE -ne 0) { throw 'push failed' }

Write-Host ''
Write-Host 'main synced. https://github.com/laow07573-web/daimao-quiz-master' -ForegroundColor Green
