@echo off
rem Reformat GDScript in place with gdformat. Commits are cheap - do one first.
set /p ok=This REWRITES every .gd file (gdformat). Commit first. Continue? (y/N)
if /i not "%ok%"=="y" (
    echo Cancelled.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\gd_toolkit.ps1" -Fix
pause
