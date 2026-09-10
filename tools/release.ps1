# 一键出包：语法检查 → 回归自检 → 导出 → 同步交付物 → 冒烟 → 提交。
# 任何一步硬失败就停下，不会带着问题往下走（也就不会再出现"exe 和源码不同步"）。
#   powershell -File tools\release.ps1 -Msg "修了什么"
#   可选开关：-SkipTests 跳过自检  -Windowed 连需要窗口模式的自检一起跑（会弹窗口）
#             -NoCommit 只跑到冒烟不提交  -ExportOnly 只导出
param(
    [string]$Msg = '',
    [switch]$SkipTests,
    [switch]$Windowed,
    [switch]$NoCommit,
    [switch]$ExportOnly
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$started = Get-Date
$proj = Split-Path -Parent $PSScriptRoot
Set-Location $proj

# ---------- 小工具 ----------
function Step($name, $color) { Write-Host "`n== $name ==" -ForegroundColor $color }
function Fail($why) {
    Write-Host "`n[中止] $why" -ForegroundColor Red
    Write-Host ("耗时 {0:N0} 秒；前面已完成的步骤不会自动回滚。" -f ((Get-Date) - $started).TotalSeconds)
    exit 1
}
function Find-Godot {
    foreach ($c in @(
        'e:\游戏工具\Godot\Godot_v4.7.2-stable_win64_console.exe',
        'e:\工具\Godot\Godot_v4.7.2-stable_win64_console.exe')) {
        if (Test-Path $c) { return $c }
    }
    foreach ($r in @('e:\游戏工具', 'e:\工具', 'D:\工具')) {
        if (-not (Test-Path $r)) { continue }
        $hit = Get-ChildItem -Path $r -Filter 'Godot_v4*console.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return ''
}
function Find-Bash {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $bin = Split-Path -Parent $git.Source                 # ...\git\mingw64\bin
        $up1 = Split-Path -Parent $bin                        # ...\git\mingw64
        $up2 = Split-Path -Parent $up1                         # ...\git
        foreach ($base in @($up2, $up1)) {
            foreach ($p in @((Join-Path $base 'bin\bash.exe'), (Join-Path $base 'usr\bin\bash.exe'))) {
                if (Test-Path $p) { return $p }
            }
        }
    }
    foreach ($p in @('C:\Program Files\Git\bin\bash.exe', 'C:\Program Files (x86)\Git\bin\bash.exe')) {
        if (Test-Path $p) { return $p }
    }
    return ''
}

$godot = Find-Godot
if (-not $godot) { Fail '找不到 Godot 控制台版，请检查 E:\游戏工具\Godot' }
Write-Host "Godot : $godot"
Write-Host "工程  : $proj"

# ---------- 0 前置检查 ----------
Step '0/6 前置检查' Cyan
$running = Get-Process | Where-Object { $_.ProcessName -match '全是神人|^game$' }
if ($running) { Fail "游戏还在跑（$($running.ProcessName -join ', ')），先关掉再出包" }
$dirty = git status --porcelain --untracked-files=no
Write-Host "未提交改动：$(@($dirty).Count) 个文件"

# ---------- 1 全量语法检查 ----------
Step '1/6 全量语法检查' Cyan
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$syn = & $godot --headless --path . --script 'res://tools/check_all_scripts.gd' 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
$syn | Select-String '^BAD ' | ForEach-Object { Write-Host "   $($_.Line)" -ForegroundColor Yellow }
$sum = $syn | Select-String '语法检查：' | Select-Object -Last 1
if ($sum) { Write-Host "   $($sum.Line)" } else { Write-Host '   检查器没输出，本身没跑起来' -ForegroundColor Yellow }
if ($code -ne 0 -or -not $sum) { Fail '语法检查没过' }

# ---------- 2 回归自检 ----------
if (-not $SkipTests -and -not $ExportOnly) {
    Step '2/6 回归自检' Cyan
    $bash = Find-Bash
    if (-not $bash) { Fail '找不到 bash（Git 自带），无法跑 run_selftests.sh' }
    $args2 = @('tools/run_selftests.sh')
    if ($Windowed) { $args2 = @('tools/run_selftests.sh', '--all') }
    & $bash $args2
    if ($LASTEXITCODE -ne 0) { Fail '自检没过，看上面的 FAIL/TIMEOUT' }
} else {
    Step '2/6 回归自检（已跳过）' DarkGray
}

# ---------- 3 导出 ----------
Step '3/6 导出 exe' Cyan
$latestSrc = (Get-ChildItem -Path 'scripts', 'scenes', 'assets', 'shaders', 'addons' -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
$out = & $godot --headless --path . --export-release 'Windows Desktop' 'build/out_game.exe' 2>&1
$errs = @($out | Select-String '^ERROR')
if ($errs.Count -gt 0) { $errs | Select-Object -First 3 | ForEach-Object { Write-Host "   $($_.Line)" -ForegroundColor Yellow } }
if (-not (Test-Path 'build/out_game.exe')) { Fail '导出没产物' }
$made = (Get-Item 'build/out_game.exe').LastWriteTime
if ($made -lt $latestSrc) { Fail "导出的还是旧的（exe $made 比最新源码 $latestSrc 还早）" }
Write-Host ("导出完成：{0:N0} 字节，{1}" -f (Get-Item 'build/out_game.exe').Length, $made)
if ($ExportOnly) { Write-Host "`n只导出，结束。"; exit 0 }

# ---------- 4 同步交付物 ----------
Step '4/6 同步 build/全是神人.exe 与 web/files' Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'repackage.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'repackage 失败' }
$exe = Join-Path $proj 'build\全是神人.exe'
if (-not (Test-Path -LiteralPath $exe)) { Fail '没有 build\全是神人.exe' }
Write-Host ("本体：{0:N0} 字节" -f (Get-Item -LiteralPath $exe).Length)

# ---------- 5 冒烟 ----------
Step '5/6 冒烟启动（跑 700 帧自动退出）' Cyan
$prev2 = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$smoke = Start-Process -FilePath $exe -ArgumentList '--quit-after', '700' -PassThru -Wait `
    -RedirectStandardOutput 'build/.smoke_out.txt' -RedirectStandardError 'build/.smoke_err.txt'
$ErrorActionPreference = $prev2
$serr = @()
if (Test-Path 'build/.smoke_err.txt') { $serr = @(Get-Content 'build/.smoke_err.txt' | Select-String 'SCRIPT ERROR') }
Write-Host "退出码 $($smoke.ExitCode)；脚本错误 $($serr.Count) 条"
if ($serr.Count -gt 0) { $serr | Select-Object -First 4 | ForEach-Object { Write-Host "   $($_.Line)" -ForegroundColor Yellow } }
if ($smoke.ExitCode -ne 0) { Fail "冒烟退出码 $($smoke.ExitCode)" }
if ($serr.Count -gt 0) { Fail '冒烟阶段有 SCRIPT ERROR' }

# ---------- 6 提交 ----------
if ($NoCommit) {
    Step '6/6 提交（已按要求跳过）' DarkGray
} else {
    Step '6/6 提交' Cyan
    if ($Msg -eq '') { $Msg = "出包 $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
    $prev3 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    git add -A
    $staged = @(git diff --cached --name-only)
    if ($staged.Count -eq 0) {
        Write-Host '没有待提交的改动，跳过'
    } else {
        git -c user.name='千问办公' -c user.email='assistant@local' commit -m $Msg | Out-Null
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev3
        if ($code -ne 0) { Fail '提交失败' }
        Write-Host "已提交 $($staged.Count) 个文件：$Msg"
    }
    $ErrorActionPreference = $prev3
}

$secs = ((Get-Date) - $started).TotalSeconds
Write-Host ''
Write-Host "全部通过，耗时 $([math]::Round($secs)) 秒。" -ForegroundColor Green
Write-Host "交付物：build\全是神人.exe   网页待上传：web\files\game.exe"
Write-Host "要上云：git push origin main"
