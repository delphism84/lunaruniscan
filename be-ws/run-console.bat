@echo off
setlocal

REM Run UniScan BE (single instance) and keep console open with logs.
REM Ctrl+C to stop.
REM Examples:
REM   run-console.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-single.ps1" -Console %*
exit /b %ERRORLEVEL%

