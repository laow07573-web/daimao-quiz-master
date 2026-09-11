# 强制将猫卷窗口置于前台并点击指定客户区坐标
# 用法: powershell -File click_app.ps1 <客户区X比例 0-1> <客户区Y比例 0-1> [截图输出路径]
param(
    [double]$rx = 0.5,
    [double]$ry = 0.94,
    [string]$shot = ''
)

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Fore {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    public struct RECT { public int Left, Top, Right, Bottom; }
    public struct POINT { public int X, Y; }
}
'@

$p = Get-Process flashcard_app -ErrorAction Stop
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { Write-Output '未找到主窗口'; exit 1 }

# --- 前台锁定绕过：AttachThreadInput ---
$fg = [Fore]::GetForegroundWindow()
$fgpid = 0
[Fore]::GetWindowThreadProcessId($fg, [ref]$fgpid) | Out-Null
$myTid = [Fore]::GetCurrentThreadId()
$fgTid = [Fore]::GetWindowThreadProcessId($fg, [ref]$fgpid)
[Fore]::AttachThreadInput($myTid, $fgTid, $true) | Out-Null
[Fore]::ShowWindow($h, 9) | Out-Null      # SW_RESTORE
[Fore]::BringWindowToTop($h) | Out-Null
[Fore]::SetForegroundWindow($h) | Out-Null
[Fore]::AttachThreadInput($myTid, $fgTid, $false) | Out-Null
Start-Sleep -Milliseconds 800

$now = [Fore]::GetForegroundWindow()
Write-Output ("前台已切换: " + ($now -eq $h))

# --- 点击 ---
$c = New-Object Fore+RECT
[Fore]::GetClientRect($h, [ref]$c) | Out-Null
$cw = $c.Right; $ch = $c.Bottom
$x = [int]($cw * $rx); $y = [int]($ch * $ry)
$pt = New-Object Fore+POINT
$pt.X = $x; $pt.Y = $y
[Fore]::ClientToScreen($h, [ref]$pt) | Out-Null
Write-Output "客户区 ($x,$y) -> 屏幕 ($($pt.X),$($pt.Y))"
[Fore]::SetCursorPos($pt.X, $pt.Y) | Out-Null
Start-Sleep -Milliseconds 120
[Fore]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 70
[Fore]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
Write-Output '点击完成'

# --- 截图 ---
if ($shot -ne '') {
    Start-Sleep -Milliseconds 900
    $r = New-Object Fore+RECT
    [Fore]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "截图: $shot (${w}x${ht})"
}
