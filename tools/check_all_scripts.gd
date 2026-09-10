extends SceneTree
## 一次启动把所有 .gd 走一遍 load()，解析错误当场报出来。
## 比"每个文件 --check-only"快一个数量级（省掉几十次引擎启动），本机与 CI 都用它。
##   godot --headless --path . --script res://tools/check_all_scripts.gd
## 退出码：0=全过，1=有脚本加载失败。
const ROOTS := ["res://scripts", "res://tools", "res://addons", "res://shaders"]
var _bad := 0
var _total := 0

func _init() -> void:
	var files: Array[String] = []
	for r in ROOTS:
		_walk(r, files)
	files.sort()
	for f in files:
		_total += 1
		var s = load(f)
		if s == null:
			_bad += 1
			print("BAD  " + f)
	print("== 语法检查：%d 个脚本，%d 个加载失败 ==" % [_total, _bad])
	quit(1 if _bad > 0 else 0)

func _walk(path: String, out: Array[String]) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n == "." or n == "..":
			n = d.get_next()
			continue
		var p := path.path_join(n)
		if d.current_is_dir():
			_walk(p, out)
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()
