package com.flashcard.app;

import android.Manifest;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;
import android.text.TextUtils;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.security.MessageDigest;
import java.util.HashSet;
import java.util.Set;

public class MainActivity extends FlutterActivity {
    private static final String TAMPER_CHANNEL = "com.flashcard.app/tamper";
    private static final String KEEPALIVE_CHANNEL = "com.flashcard.app/keepalive";
    private static final String NOTIFICATION_CHANNEL = "com.flashcard.app/notification";
    private static final int REQ_NOTIFICATION_PERMISSION = 2001;

    /** 无障碍服务完整组件名（ComponentName.flattenToString 形式） */
    private static final String ACCESSIBILITY_COMPONENT =
            new ComponentName("com.flashcard.app",
                    "com.flashcard.app.KeepAliveAccessibilityService").flattenToString();

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // 防篡改签名校验
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), TAMPER_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("getSignatureHash")) {
                    try {
                        android.content.pm.PackageInfo info = getPackageManager().getPackageInfo(
                                getPackageName(),
                                android.content.pm.PackageManager.GET_SIGNATURES);
                        android.content.pm.Signature sig = info.signatures[0];
                        MessageDigest md = MessageDigest.getInstance("SHA-256");
                        byte[] hash = md.digest(sig.toByteArray());
                        String base64 = android.util.Base64.encodeToString(hash,
                                android.util.Base64.NO_WRAP);
                        result.success(base64.substring(0, 16));
                    } catch (Exception e) {
                        result.error("SIG_ERROR", e.getMessage(), null);
                    }
                } else {
                    result.notImplemented();
                }
            });

        // v1.0.2: 无障碍保活
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), KEEPALIVE_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("isAccessibilityEnabled")) {
                    result.success(isAccessibilityServiceEnabled());
                } else if (call.method.equals("openAccessibilitySettings")) {
                    try {
                        Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        result.success(true);
                    } catch (Exception e) {
                        result.error("INTENT_ERROR", e.getMessage(), null);
                    }
                } else if (call.method.equals("isIgnoringBatteryOptimizations")) {
                    // 与里程碑一致：设置页可引导用户忽略电池优化，保提醒服务不被系统清理
                    PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
                    result.success(pm.isIgnoringBatteryOptimizations(getPackageName()));
                } else if (call.method.equals("requestIgnoreBatteryOptimizations")) {
                    try {
                        Intent intent = new Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:" + getPackageName()));
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        result.success(true);
                    } catch (Exception e) {
                        result.error("INTENT_ERROR", e.getMessage(), null);
                    }
                } else {
                    result.notImplemented();
                }
            });

        // v1.0.2 修复: Android 13+ 通知运行时权限（提醒/测试通知前请求）
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), NOTIFICATION_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("requestNotificationPermission")) {
                    if (Build.VERSION.SDK_INT >= 33) {
                        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                                == PackageManager.PERMISSION_GRANTED) {
                            result.success(true);
                        } else {
                            requestPermissions(
                                    new String[]{Manifest.permission.POST_NOTIFICATIONS},
                                    REQ_NOTIFICATION_PERMISSION);
                            result.success(false);
                        }
                    } else {
                        result.success(true);
                    }
                } else if (call.method.equals("hasNotificationPermission")) {
                    if (Build.VERSION.SDK_INT >= 33) {
                        result.success(checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                                == PackageManager.PERMISSION_GRANTED);
                    } else {
                        result.success(true);
                    }
                } else {
                    result.notImplemented();
                }
            });
    }

    /**
     * 判断无障碍服务是否开启。
     * 必须用 ComponentName(...).flattenToString() 匹配系统设置值
     * （缩写形式匹配不上会误报「未开启」）。
     */
    private boolean isAccessibilityServiceEnabled() {
        String enabledServices = Settings.Secure.getString(
                getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (TextUtils.isEmpty(enabledServices)) return false;
        Set<String> enabled = new HashSet<>();
        for (String s : enabledServices.split(":")) {
            if (!s.isEmpty()) enabled.add(s);
        }
        return enabled.contains(ACCESSIBILITY_COMPONENT);
    }
}
