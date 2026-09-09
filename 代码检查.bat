@echo off
rem GDScript health check: gdlint + gdformat dry-run. Read-only, changes no file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\gd_toolkit.ps1"
pause
