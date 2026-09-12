@echo off
rem One-click dialogue preview (no need to boot the game).
rem   double-click        -> list all scripts and preview the first
rem   this.bat 2          -> preview the 2nd script by index (use the number, ASCII-safe)
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\dialogue_preview.ps1" %*
pause
