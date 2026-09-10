#!/usr/bin/env bash
# 跑 tools/selftests/ 下的回归自检。工程内脚本，本机与 CI 通用。
#   bash tools/run_selftests.sh                 # 无头跑全部（跳过 window_only.txt 里标了的）
#   bash tools/run_selftests.sh --all           # 连需要窗口模式的一起跑（会弹窗口）
#   GODOT_BIN=/path/to/godot bash tools/run_selftests.sh
# 退出码：0=全过，1=有失败/超时，2=没找到 Godot
set -u
cd "$(dirname "$0")/.."
PROJ="$PWD"
ONLY_WINDOWED=0
RUN_WINDOWED=0
for a in "$@"; do
	[ "$a" = "--all" ] && RUN_WINDOWED=1
	[ "$a" = "--windowed-only" ] && { RUN_WINDOWED=1; ONLY_WINDOWED=1; }
done

# ---- 定位 Godot：优先环境变量，再试常见落点 ----
G="${GODOT_BIN:-}"
if [ -z "$G" ]; then
	for c in \
		"/e/游戏工具/Godot/Godot_v4.7.2-stable_win64_console.exe" \
		"E:/游戏工具/Godot/Godot_v4.7.2-stable_win64_console.exe" \
		"./Godot_v4.7.2-stable_linux.x86_64" \
		"/usr/local/bin/godot" "godot"; do
		if command -v "$c" >/dev/null 2>&1 || [ -f "$c" ]; then G="$c"; break; fi
	done
fi
if [ -z "$G" ]; then echo "找不到 Godot，请设 GODOT_BIN 环境变量"; exit 2; fi
echo "Godot: $G"
echo "工程 : $PROJ"

WL="$PROJ/tools/selftests/window_only.txt"
skip_for_windowed() {
	[ "$RUN_WINDOWED" = "1" ] && return 1
	[ -f "$WL" ] && grep -qxF "$1" "$WL"
}

pass=0; fail=0; skip=0
report=""
for f in "$PROJ"/tools/selftests/*.gd; do
	base="$(basename "$f")"
	case "$base" in
		pvp_bot_client.gd|st_paths.gd) continue ;;
	esac
	if [ "$ONLY_WINDOWED" = "1" ]; then
		grep -qxF "$base" "$WL" 2>/dev/null || { continue; }
	else
		if skip_for_windowed "$base"; then
			echo "SKIP $base  （需要窗口模式）"
			skip=$((skip + 1)); continue
		fi
	fi
	out="$(timeout 200 "$G" --headless --path . --script "res://tools/selftests/$base" 2>&1)"
	rc=$?
	line="$(printf '%s' "$out" | grep -a "项失败" | tail -1 | tr -d '\r')"
	if [ "$rc" = "124" ]; then
		verdict="TIMEOUT"; fail=$((fail + 1))
	elif [ -z "$line" ]; then
		verdict="NO-RESULT"; fail=$((fail + 1))
		line="$(printf '%s' "$out" | grep -aE "SCRIPT ERROR|Can't load" | head -1)"
	elif printf '%s' "$line" | grep -q "：0 项失败\|: 0 项失败\| 0 项失败"; then
		verdict="PASS"; pass=$((pass + 1))
	else
		verdict="FAIL"; fail=$((fail + 1))
	fi
	printf '%-6s %-28s %s\n' "$verdict" "$base" "$line"
	report="$report$verdict	$base	$line
"
done

echo "----"
echo "通过 $pass  失败 $fail  跳过 $skip"
[ "$fail" = "0" ] || exit 1
exit 0
