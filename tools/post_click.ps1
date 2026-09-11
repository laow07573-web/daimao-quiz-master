# 通过 PostMessage 向猫卷窗口投递鼠标点击（无需前台）
# 用法: powershell -File post_click.ps1 <客户区X比例> <客户区Y比例>
param([double]$rx = 0.5, [double]$ry = 0.94)

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class CM {
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

$p = Get-Process flashcard_app -ErrorAction Stop
$h = $p.MainWindowHandle
$c = New-Object CM+RECT
[CM]::GetClientRect($h, [ref]$c) | Out-Null
$cw = $c.Right; $ch = $c.Bottom
$x = [int]($cw * $rx); $y = [int]($ch * $ry)
$lpVal = (($y -shl 16) -bor ($x -band 0xFFFF))
$lp = [IntPtr]$lpVal
Write-Output ("客户区点击 ({0},{1})  client={2}x{3}" -f $x, $y, $cw, $ch)

[CM]::PostMessage($h, 0x0200, [IntPtr]::Zero, $lp) | Out-Null
Start-Sleep -Milliseconds 90
[CM]::PostMessage($h, 0x0201, [IntPtr]1, $lp) | Out-Null
Start-Sleep -Milliseconds 90
[CM]::PostMessage($h, 0x0202, [IntPtr]::Zero, $lp) | Out-Null
Write-Output '已投递点击消息'
