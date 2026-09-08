@echo off
rem Dev-only LOC report. All Chinese text lives in tools\loc_report.ps1 (UTF-8 BOM)
rem so cmd.exe never has to parse non-ASCII bytes from this file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\loc_report.ps1"
pause
exit /b %errorlevel%
