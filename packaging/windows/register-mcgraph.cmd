@echo off
rem Runs register-mcgraph.ps1 (beside this file) past the default execution policy, which blocks a downloaded .ps1 on a stock Windows 11.
rem Arguments pass through (-Remove undoes the registration); the exit code is PowerShell's.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0register-mcgraph.ps1" %*
exit /b %ERRORLEVEL%
