@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build_WinSukkiri_v1.1.ps1"
echo.
pause
