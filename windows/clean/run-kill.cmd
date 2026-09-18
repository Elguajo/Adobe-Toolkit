@echo off
setlocal
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Run this file as Administrator.
    pause
    exit /b 1
)

echo --- Adobe Environment Toolkit: stopping processes and services ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AdobeCleaner.ps1" -Mode KillOnly
if %errorLevel% neq 0 (
    echo [ERROR] PowerShell step failed.
    pause
    exit /b 1
)
echo --- Done ---
pause
