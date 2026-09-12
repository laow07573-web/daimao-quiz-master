@echo off
REM MaoJuan baseline verify entry (calls verify_reference.ps1)
REM Usage: verify_reference.bat [APK path]
powershell -ExecutionPolicy Bypass -File "%~dp0verify_reference.ps1" %*
