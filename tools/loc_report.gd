extends SceneTree
## 开发者用的代码行数统计（不进游戏、游戏内不显示任何东西）。
## 跑法（秒级完成，远小于 30 秒）：
##   Godot --headless --path 项目 --script res://tools/loc_report.gd
## 或直接双击项目根目录的「统计代码.bat」。
## 输出：控制台分组明细 + 写一份 docs/代码统计.md（含每个部分、每个文件多少行）。

const ROOT := "res://"
# 统计范围：目录前缀 → 分区名（顺序即报告里的展示顺序）
const SECTIONS := {
	"scripts/pvp/": "联机 PVP（大厅/竞技场/玩家/地图/HUD/发现）",
	"scripts/": "单机玩法（玩家/武器/技能/BOSS/地形/背包/HUD…）",
	"addons/": "第三方插件（血条控件）",
	"shaders/": "着色器",
	"scenes/": "场景文件",
	"tools/": "开发者工具",
}
const SKIP_DIRS := [".godot", "build", "web", "docs", ".git"]

var _rows := {}        # 分区 → Array[{path, lines, code, comment, blank}]
var _totals := {}      # 分区 → {lines, code, comment, blank}
var _t0 := 0


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	for prefix in SECTIONS:
		_walk(ROOT + prefix, prefix)
	_report()
	quit(0)


func _walk(dir_path: String, section: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not name.begins_with(".") and not name.ends_with(".uid"):
			var full := dir_path.path_join(name)
			if d.current_is_dir():
				if not SKIP_DIRS.has(name):
					_walk(full, section)
			elif name.ends_with(".gd") or name.ends_with(".gdshader") or name.ends_with(".tscn"):
				_count(full, section)
		name = d.get_next()
	d.list_dir_end()


func _count(file: String, section: String) -> void:
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return
	var is_gd := file.ends_with(".gd")
	var lines := 0
	var code := 0
	var comment := 0
	var blank := 0
	while not f.eof_reached():
		var s := f.get_line().strip_edges()
		lines += 1
		if s.is_empty():
			blank += 1
		elif is_gd and s.begins_with("#"):
			comment += 1
		else:
			code += 1
	if lines <= 0:
		return
	if not _rows.has(section):
		_rows[section] = []
		_totals[section] = {"lines": 0, "code": 0, "comment": 0, "blank": 0}
	_rows[section].append({"path": file.replace("res://", ""), "lines": lines,
		"code": code, "comment": comment, "blank": blank})
	var t: Dictionary = _totals[section]
	t.lines += lines
	t.code += code
	t.comment += comment
	t.blank += blank


func _report() -> void:
	var md: Array[String] = []
	md.append("# 代码统计")
	md.append("")
	md.append("> 由 tools/loc_report.gd 生成（开发者工具，游戏内不显示）。")
	md.append("")
	var sum_lines := 0
	var sum_code := 0
	var sum_comment := 0
	var sum_blank := 0
	var sum_files := 0
	for section in SECTIONS:
		if not _totals.has(section):
			continue
		var t: Dictionary = _totals[section]
		var rows: Array = _rows[section]
		rows.sort_custom(func(a, b): return int(a.lines) > int(b.lines))
		sum_lines += int(t.lines)
		sum_code += int(t.code)
		sum_comment += int(t.comment)
		sum_blank += int(t.blank)
		sum_files += rows.size()
		md.append("## %s" % String(SECTIONS[section]))
		md.append("")
		md.append("小计 **%d 行**（代码 %d / 注释 %d / 空行 %d，%d 个文件）" % [
			int(t.lines), int(t.code), int(t.comment), int(t.blank), rows.size()])
		md.append("")
		md.append("| 文件 | 行数 | 代码 | 注释 | 空行 |")
		md.append("|---|---:|---:|---:|---:|")
		for r in rows:
			md.append("| %s | %d | %d | %d | %d |" % [
				String(r.path), int(r.lines), int(r.code), int(r.comment), int(r.blank)])
		md.append("")
		print("\n== %s ==" % String(SECTIONS[section]))
		print("   小计 %d 行（代码 %d / 注释 %d / 空行 %d）" % [
			int(t.lines), int(t.code), int(t.comment), int(t.blank)])
		for r in rows:
			print("   %6d  %s" % [int(r.lines), String(r.path)])
	md.append("## 合计")
	md.append("")
	md.append("- 总行数 **%d**（代码 %d / 注释 %d / 空行 %d）" % [sum_lines, sum_code, sum_comment, sum_blank])
	md.append("- 文件数 **%d**" % sum_files)
	print("\n== 合计 ==")
	print("   总行数 %d（代码 %d / 注释 %d / 空行 %d），文件 %d 个，耗时 %d 毫秒" % [
		sum_lines, sum_code, sum_comment, sum_blank, sum_files, Time.get_ticks_msec() - _t0])
	var dir := DirAccess.open("res://docs")
	if dir == null:
		DirAccess.make_dir_recursive_absolute("res://docs")
	var f := FileAccess.open("res://docs/代码统计.md", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(md) + "\n")
		print("   报告已写入 res://docs/代码统计.md")
