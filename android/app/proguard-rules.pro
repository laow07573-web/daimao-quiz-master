# MaoJuan · R8 keep / dontwarn 规则
#
# 背景：google_mlkit_text_recognition 把四个语种识别器包都声明为 compileOnly
# （由 App 自己引入用到的语种），但插件 Java 代码里有一个覆盖四个语种的 switch。
# 本 App 只用中文（lib/services/ocr_service.dart → TextRecognitionScript.chinese，
# 对应依赖见 android/app/build.gradle 的 text-recognition-chinese）。中文包是真
# 依赖，故意不写 -dontwarn：万一哪天依赖被删，R8 要能立刻报出来。
# 其余三个语种在运行时不可达，但 R8 会因为找不到这些类而让 release 构建失败：
#   ERROR: Missing classes detected while running R8 ...（实测 2026-10-01）
# 下面三条即 AGP 自动生成的
# build/app/outputs/mapping/release/missing_rules.txt 里除中文以外的内容。
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
