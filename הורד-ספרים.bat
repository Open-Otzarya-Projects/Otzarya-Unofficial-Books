@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0הורדת-ספרים.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo Error code: %ERRORLEVEL%
    pause
)
