extends SceneTree
## 诊断落盘自检（需要窗口模式：要真的渲出一帧才有截图）
##   godot --path . --script res://tools/selftests/diag_selftest.gd
## 查三件事：引擎文件日志开关是否打开、F12 是否真落一张 png + 一段快照、日志目录是否可打开。
var _fails := 0

func _ok(cond: bool, msg: String) -> void:
	print(("  ok   | " if cond else "  FAIL | ") + msg)
	if not cond:
		_fails += 1

func _init() -> void:
	print("== 诊断落盘自检 ==")
	# 主场景跑起来，保证有 viewport 与玩家之外的真实内容
	var scene: Node = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 40:
		await process_frame

	var diag := root.get_node_or_null("Diag")
	_ok(diag != null, "自动加载 Diag 存在")
	if diag == null:
		_done()
		return

	_ok(bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging")),
		"引擎文件日志已打开（导出包里报错才会落盘）")

	var dir := String(diag.call("dump_now"))
	_ok(dir != "", "dump_now() 返回了日志目录：" + dir)

	var d := DirAccess.open(dir)
	_ok(d != null, "日志目录能打开")
	if d == null:
		_done()
		return
	var shots: Array[String] = []
	var diags: Array[String] = []
	for f in d.get_files():
		if f.begins_with("shot-") and f.ends_with(".png"):
			shots.append(f)
		if f.begins_with("diag-") and f.ends_with(".log"):
			diags.append(f)
	_ok(not shots.is_empty(), "按 F12 后目录里有截图 png（%d 张）" % shots.size())
	_ok(not diags.is_empty(), "有 diag-*.log 心跳日志（%d 份）" % diags.size())
	if not shots.is_empty():
		shots.sort()
		var sz := FileAccess.get_file_as_bytes(dir.path_join(shots[shots.size() - 1])).size()
		_ok(sz > 2048, "最新那张截图有实际内容（%d 字节）" % sz)
	if not diags.is_empty():
		diags.sort()
		var txt := FileAccess.get_file_as_string(dir.path_join(diags[diags.size() - 1]))
		_ok(txt.contains("F12 手动快照"), "日志里写了手动快照那一节")
		_ok(txt.contains("心跳"), "日志里有心跳行")
		_ok(txt.contains("引擎   :"), "日志里有启动横幅（引擎版本）")
	_done()

func _done() -> void:
	print("== 诊断落盘自检结果：%d 项失败 ==" % _fails)
	quit(1 if _fails > 0 else 0)
