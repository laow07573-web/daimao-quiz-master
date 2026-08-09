package com.flashcard.app;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.view.accessibility.AccessibilityEvent;

/**
 * 无障碍保活服务（v1.0.2）
 * 服务被系统强杀后会自动重启并拉起 App（参考 GKD 策略）。
 * 无需处理具体无障碍事件，保持运行即可。
 */
public class KeepAliveAccessibilityService extends AccessibilityService {
    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        // 服务连接时确保 App 进程被拉起
        Intent launcher = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launcher != null) {
            launcher.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(launcher);
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // 保活用，无需处理事件
    }

    @Override
    public void onInterrupt() {
        // 保活用
    }
}
