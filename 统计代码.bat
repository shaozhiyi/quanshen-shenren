@echo off
chcp 65001 >nul
REM 开发者工具：统计代码行数（游戏内不显示）。报告同时写入 docs\代码统计.md
"e:\工具\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0" --script res://tools/loc_report.gd
echo.
pause
