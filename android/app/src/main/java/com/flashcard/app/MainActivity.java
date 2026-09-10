package com.flashcard.app;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.security.MessageDigest;

public class MainActivity extends FlutterActivity {
    private static final String TAMPER_CHANNEL = "com.flashcard.app/tamper";
    private static final String KEEPALIVE_CHANNEL = "com.flashcard.app/keepalive";
    private static final String NOTIFICATION_CHANNEL = "com.flashcard.app/notification";
    private static final String SYNC_CHANNEL = "com.flashcard.app/sync";
    private static final int REQ_NOTIFICATION_PERMISSION = 2001;

    // 局域网同步（v11）：Wi-Fi 默认丢弃广播/多播 UDP 包，
    // 持有 MulticastLock 才能收到对端发现信标（需 CHANGE_WIFI_MULTICAST_STATE）
    private android.net.wifi.WifiManager.MulticastLock multicastLock;

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
                                android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES);
                        android.content.pm.Signature sig;
                        if (info.signingInfo != null
                                && info.signingInfo.getApkContentsSigners() != null
                                && info.signingInfo.getApkContentsSigners().length > 0) {
                            // API 28+ 推荐：APK contents signer（v2/v3 签名真实证书）
                            sig = info.signingInfo.getApkContentsSigners()[0];
                        } else {
                            sig = info.signatures[0];
                        }
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

        // v1.0.2 设计审查修复（简化保活）：移除无障碍保活通道，
        // 仅保留电池优化豁免（前台提醒服务不被系统激进清理）
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), KEEPALIVE_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("isIgnoringBatteryOptimizations")) {
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

        // 局域网同步（v11）：组播/广播锁，保证 Wi-Fi 下能收到对端信标。
        // 引擎启动时获取、退出时释放；失败时如实报错由 Dart 侧降级处理。
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SYNC_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("acquireMulticastLock")) {
                    try {
                        android.net.wifi.WifiManager wm = (android.net.wifi.WifiManager)
                                getApplicationContext().getSystemService(WIFI_SERVICE);
                        if (multicastLock == null) {
                            multicastLock = wm.createMulticastLock("flashcard_sync");
                            multicastLock.setReferenceCounted(false);
                        }
                        if (!multicastLock.isHeld()) {
                            multicastLock.acquire();
                        }
                        result.success(true);
                    } catch (Exception e) {
                        result.error("MULTICAST_ERROR", e.getMessage(), null);
                    }
                } else if (call.method.equals("releaseMulticastLock")) {
                    try {
                        if (multicastLock != null && multicastLock.isHeld()) {
                            multicastLock.release();
                        }
                        result.success(true);
                    } catch (Exception e) {
                        result.error("MULTICAST_ERROR", e.getMessage(), null);
                    }
                } else {
                    result.notImplemented();
                }
            });
    }
}
