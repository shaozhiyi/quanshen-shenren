# 对话预览：找到 Godot，窗口模式跑 tools/dialogue_preview.gd，把序号参数透传过去。
#   powershell -File tools\dialogue_preview.ps1        # 预览第一段并列出全部
#   powershell -File tools\dialogue_preview.ps1 2      # 预览第 2 段
param([string]$Pick = '')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$proj = Split-Path -Parent $PSScriptRoot

$godot = ''
foreach ($c in @(
    'e:\游戏工具\Godot\Godot_v4.7.2-stable_win64_console.exe',
    'e:\工具\Godot\Godot_v4.7.2-stable_win64_console.exe')) {
    if (Test-Path $c) { $godot = $c; break }
}
if ($godot -eq '') {
    $hit = Get-ChildItem -Path @('e:\游戏工具', 'e:\工具') -Filter 'Godot_v4*console.exe' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($hit) { $godot = $hit.FullName }
}
if ($godot -eq '') { Write-Host '找不到 Godot 控制台版，请检查 E:\游戏工具\Godot' -ForegroundColor Red; exit 1 }

$argv = @('--path', $proj, '--resolution', '1280x720', '--script', 'res://tools/dialogue_preview.gd')
if ($Pick -ne '') { $argv += @('--', $Pick) }
Write-Host "Godot : $godot"
Write-Host "预览  : $(if ($Pick -eq '') { '第一段' } else { "#$Pick" })"
& $godot @argv
