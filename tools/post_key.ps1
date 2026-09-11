# 向猫卷窗口投递键盘 Tab/方向键（Flutter 桌面支持键盘导航）
# 用法: powershell -File post_key.ps1 <虚拟键码> [次数]
param([int]$vk = 9, [int]$times = 1)

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class PK {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
'@

$p = Get-Process flashcard_app -ErrorAction Stop
$h = $p.MainWindowHandle
for ($i = 0; $i -lt $times; $i++) {
    [PK]::PostMessage($h, 0x0100, [IntPtr]$vk, [IntPtr]0) | Out-Null   # WM_KEYDOWN
    Start-Sleep -Milliseconds 60
    [PK]::PostMessage($h, 0x0101, [IntPtr]$vk, [IntPtr]0) | Out-Null   # WM_KEYUP
    Start-Sleep -Milliseconds 120
}
Write-Output ("已投递键码 $vk x$times")
