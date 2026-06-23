package com.flashcard.app;

import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.security.MessageDigest;
import java.util.Base64;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.flashcard.app/tamper";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("getSignatureHash")) {
                    try {
                        PackageInfo info = getPackageManager().getPackageInfo(
                            getPackageName(), PackageManager.GET_SIGNATURES);
                        Signature sig = info.signatures[0];
                        MessageDigest md = MessageDigest.getInstance("SHA-256");
                        byte[] hash = md.digest(sig.toByteArray());
                        String base64 = Base64.getEncoder().encodeToString(hash);
                        result.success(base64.substring(0, 16));
                    } catch (Exception e) {
                        result.error("SIG_ERROR", e.getMessage(), null);
                    }
                } else {
                    result.notImplemented();
                }
            });
    }
}
