@echo off
rem One-click release pipeline: syntax check -> regression selftests -> export -> sync web/files -> smoke -> commit.
rem Usage: double-click, or pass a commit message:  this.bat fixed the dash bug
setlocal
set "MSG=%*"
if "%MSG%"=="" set /p MSG=Commit message (what changed): 
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\release.ps1" -Msg "%MSG%"
pause
