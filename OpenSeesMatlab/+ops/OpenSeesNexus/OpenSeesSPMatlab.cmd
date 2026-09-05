@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OpenSeesSPMatlab.ps1" %*
exit /b %ERRORLEVEL%
