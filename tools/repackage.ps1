<#
    repackage.ps1 —— 导出后的打包脚本（只产出单个 exe，不再做 zip 分享包）
    用法：
      1) 先导出：Godot_v4.7.2 --headless --path . --export-release "Windows Desktop" build/out_game.exe
      2) 再打包：powershell -NoProfile -ExecutionPolicy Bypass -File tools\repackage.ps1
    做的事：
      · 把 build/ 里旧的 神人乱斗.exe 送进回收站（不永久删除）
      · 把 build/out_game.exe 改名为 build/神人乱斗.exe
      · 同步一份到 web/files/game.exe，并把 build/说明.txt 同步成 web/files/readme.txt
        （下载页 web/index.html 就是从这里取文件；发布网页时整个 web/ 目录上传）
      · 报告最终字节数
#>
Add-Type -AssemblyName Microsoft.VisualBasic
$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build'
$webf  = Join-Path $root 'web\files'
$exe   = Join-Path $build '神人乱斗.exe'
$tmp   = Join-Path $build 'out_game.exe'
$readme= Join-Path $build '说明.txt'

$rebuilt = Test-Path -LiteralPath $tmp
if (-not $rebuilt) {
  Write-Output 'SKIP_RENAME: 没有 build/out_game.exe，跳过导出改名，仅重新同步 web/files（适合只改了玩法说明的情况）。'
  if (-not (Test-Path -LiteralPath $exe)) { throw "既没有 $tmp 也没有 $exe，请先导出。" }
}

# 旧 exe 进回收站（可从回收站恢复）
if ($rebuilt -and (Test-Path -LiteralPath $exe)) {
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($exe, 'OnlyErrorDialogs', 'SendToRecycleBin')
  Write-Output ("TRASHED_OLD_EXE exists_now=" + (Test-Path -LiteralPath $exe))
}

if ($rebuilt) {
  Move-Item -LiteralPath $tmp -Destination $exe
}
Write-Output ("NEW_EXE_BYTES " + (Get-Item -LiteralPath $exe).Length)

# 同步下载页产物
New-Item -ItemType Directory -Force -Path $webf | Out-Null
Copy-Item -LiteralPath $exe -Destination (Join-Path $webf 'game.exe') -Force
Write-Output ("WEB_EXE_BYTES " + (Get-Item -LiteralPath (Join-Path $webf 'game.exe')).Length)
if (Test-Path -LiteralPath $readme) {
  Copy-Item -LiteralPath $readme -Destination (Join-Path $webf 'readme.txt') -Force
  Write-Output ("WEB_README_BYTES " + (Get-Item -LiteralPath (Join-Path $webf 'readme.txt')).Length)
}
Write-Output 'DONE'
