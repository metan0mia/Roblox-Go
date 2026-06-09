@echo off
chcp 65001 > nul
title ROBLOX

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

if /i "%~1"=="stop" goto stop
if /i "%~1"=="fix" goto fix
if /i "%~1"=="menu" goto menu
goto go

:go
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Roblox.ps1" -Action go
echo.
echo  Stop bypass only:  Roblox.bat stop
echo  Black screen fix:    Roblox.bat fix
pause
exit /b

:stop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Roblox.ps1" -Action stop
pause
exit /b

:fix
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Roblox.ps1" -Action fix
pause
exit /b

:menu
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Roblox.ps1" -Action menu
exit /b
