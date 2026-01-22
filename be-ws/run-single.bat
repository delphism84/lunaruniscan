@echo off
setlocal

REM Run UniScan BE (single instance) via PowerShell.
REM Usage examples:
REM   run-single.bat
REM   run-single.bat -Port 45444 -HostName 127.0.0.1 -WsPath /ws/sendReq

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-single.ps1" %*
exit /b %ERRORLEVEL%

