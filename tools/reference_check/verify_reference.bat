@echo off
REM 猫卷 · 基线对照验证入口（调用 verify_reference.ps1）
REM 用法: verify_reference.bat [APK路径]
powershell -ExecutionPolicy Bypass -File "%~dp0verify_reference.ps1" %*
