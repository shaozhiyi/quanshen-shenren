# 开发者工具：统计代码行数（游戏内不显示 anything 关于代码量）。
# 由项目根目录的「统计代码.bat」调用；也可以直接右键"使用 PowerShell 运行"。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$proj = Split-Path -Parent $PSScriptRoot

# 找 Godot 控制台版：先试已知路径，再在常见目录里搜
# 2026-09-09：全套开发工具已集中到 E:\游戏工具（旧位置 E:\工具 保留兜底）
$candidates = @(
    'e:\游戏工具\Godot\Godot_v4.7.2-stable_win64_console.exe',
    'e:\工具\Godot\Godot_v4.7.2-stable_win64_console.exe'
)
$godot = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $godot) {
    $searchRoots = @('e:\游戏工具', 'e:\工具', 'D:\工具', "$env:LOCALAPPDATA\Programs", 'C:\Program Files') | Where-Object { Test-Path $_ }
    foreach ($r in $searchRoots) {
        $hit = Get-ChildItem -Path $r -Filter 'Godot_v4*console.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { $godot = $hit.FullName; break }
    }
}
if (-not $godot) {
    Write-Host '[错误] 没找到 Godot 4 的 console 版可执行文件。' -ForegroundColor Red
    Write-Host '      请把 Godot_v4.x-stable_win64_console.exe 的路径加到本脚本顶部的 candidates 里。'
    exit 1
}

Write-Host "Godot: $godot"
Write-Host "项目:  $proj"
Write-Host ''

& $godot --headless --path $proj --script res://tools/loc_report.gd
$code = $LASTEXITCODE

Write-Host ''
if ($code -eq 0) {
    Write-Host '报告已生成：docs\代码统计.md' -ForegroundColor Green
} else {
    Write-Host "[错误] 统计脚本执行失败（退出码 $code）。请确认本文件位于项目 tools\ 目录下。" -ForegroundColor Red
}
exit $code
