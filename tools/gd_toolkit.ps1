# GDScript 代码体检（gdtoolkit）：静态检查 + 格式化。开发者工具，游戏内不显示。
#   powershell -File tools\gd_toolkit.ps1            # 只检查，不改文件
#   powershell -File tools\gd_toolkit.ps1 -Fix       # 真格式化（改文件前先 git commit）
#   powershell -File tools\gd_toolkit.ps1 -Dirs scripts,tools
param(
    [switch]$Fix,
    [string[]]$Dirs = @('scripts', 'tools', 'addons')
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$proj = Split-Path -Parent $PSScriptRoot
Set-Location $proj

# gdformat / gdlint 由 pip 装在 Python 的 Scripts 目录：先按 PATH 解析，再回退查找
function Resolve-Tool([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $py = Split-Path -Parent (Get-Command python).Source
    foreach ($d in @((Join-Path $py 'Scripts'), $py)) {
        $hit = Join-Path $d "$name.exe"
        if (Test-Path $hit) { return $hit }
    }
    return ''
}
$gdlint = Resolve-Tool 'gdlint'
$gdformat = Resolve-Tool 'gdformat'
foreach ($t in @(@('gdlint', $gdlint), @('gdformat', $gdformat))) {
    if (-not $t[1]) {
        Write-Host "[错误] 找不到 $($t[0])" -ForegroundColor Red
        Write-Host '      先执行： python -m pip install gdtoolkit'
        exit 1
    }
}

$files = Get-ChildItem -Path $Dirs -Recurse -Filter '*.gd' -ErrorAction SilentlyContinue |
    ForEach-Object { $_.FullName }
Write-Host "扫描 $($files.Count) 个 .gd 文件（$($Dirs -join ', ')）"
Write-Host ''

Write-Host '== gdlint 静态检查 ==' -ForegroundColor Cyan
# 退出码非 0 只表示"有问题"，不是失败，所以临时放开 Stop
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$report = & $gdlint $files 2>&1
$byRule = $report | Select-String '\(([a-z-]+)\)$' |
    ForEach-Object { [regex]::Match($_, '\(([a-z-]+)\)$').Groups[1].Value } |
    Group-Object | Sort-Object Count -Descending
if ($byRule) {
    foreach ($g in $byRule) { '{0,5}  {1}' -f $g.Count, $g.Name | Write-Host }
} else {
    Write-Host '没有发现问题' -ForegroundColor Green
}
Write-Host ''

Write-Host '== gdformat 格式检查 ==' -ForegroundColor Cyan
if ($Fix) {
    & $gdformat $files 2>&1 | Select-Object -Last 3
    Write-Host '已按 GDScript 官方风格重写文件，请 git diff 复核。' -ForegroundColor Yellow
} else {
    $chk = & $gdformat --check $files 2>&1
    $need = ($chk | Select-String 'would reformat').Count
    Write-Host "若不改动风格则需格式化 $need 个文件（当前仅预览，未写入）"
    Write-Host '想真格式化： powershell -File tools\gd_toolkit.ps1 -Fix' -ForegroundColor DarkGray
}
$ErrorActionPreference = $prev
