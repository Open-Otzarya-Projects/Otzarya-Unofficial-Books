@echo off
set PS1=%TEMP%\otzarya_dl.ps1
powershell -ExecutionPolicy Bypass -Command "(New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/Open-Otzarya-Projects/Otzarya-Unofficial-Books/main/הורדת-ספרים.ps1', '%PS1%')"
powershell -ExecutionPolicy Bypass -File "%PS1%"
del "%PS1%" 2>nul
