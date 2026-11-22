@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0xiaomi_privacy.ps1" %*
echo.
pause
