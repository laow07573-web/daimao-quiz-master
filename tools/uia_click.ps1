# 用 UI Automation 直接调用猫卷窗口元素的 Invoke/SelectionItem 动作（无需前台）
# 用法: powershell -File uia_click.ps1 <元素名匹配文本> [截图输出路径]
param(
    [string]$match = '统计',
    [string]$shot = ''
)

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

$p = Get-Process flashcard_app -ErrorAction Stop
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
if (-not $win) { Write-Output '未找到窗口'; exit 1 }

Write-Output ("窗口: " + $win.Current.Name)

# 深度遍历找名称匹配的元素
$all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
Write-Output ("元素总数: " + $all.Count)

$target = $null
foreach ($e in $all) {
    $n = $e.Current.Name
    if ($n -and $n.ToString().Trim() -eq $match) { $target = $e; break }
}
if (-not $target) {
    Write-Output "未找到名称=$match 的元素，列出前 40 个名称："
    $i = 0
    foreach ($e in $all) {
        if ($e.Current.Name) { Write-Output ("  [" + $i + "] " + $e.Current.Name) }
        $i++
        if ($i -gt 40) { break }
    }
    exit 0
}

Write-Output ("目标: " + $target.Current.Name + " / 类型: " + $target.Current.ControlType.ProgrammaticName)

# 依次尝试可用的 InteractionPattern
$acted = $false
try {
    $ip = $target.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $ip.Invoke(); $acted = $true; Write-Output 'Invoke 成功'
} catch { }
if (-not $acted) {
    try {
        $sp = $target.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $sp.Select(); $acted = $true; Write-Output 'Select 成功'
    } catch { }
}
if (-not $acted) {
    try {
        $lp = $target.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
        $lp.DoDefaultAction(); $acted = $true; Write-Output 'DoDefaultAction 成功'
    } catch { }
}
if (-not $acted) { Write-Output '该元素不支持任何可编程点击模式' }

Start-Sleep -Milliseconds 1200

if ($shot -ne '') {
    $r = $win.Current.BoundingRectangle
    $w = [int]$r.Width; $ht = [int]$r.Height
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([int]$r.X, [int]$r.Y, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "截图: $shot (${w}x${ht})"
}
