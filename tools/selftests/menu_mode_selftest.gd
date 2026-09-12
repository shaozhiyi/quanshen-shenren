extends SceneTree
## 主菜单模式行自检（窗口模式，要 save_png）：
##  1) 新增的 _mode_box 有两个按钮：正经模式（未制作，禁用）与雷霆模式（可点）
##  2) 正经模式按钮 disabled=true、文字含"未制作"；雷霆模式按钮 enabled、文字含"雷霆"
##  3) 原有主按钮行 _main_box 仍是 4 个（新游戏/读取存档/输入种子/联机对战），没被挤掉
##  4) 切到 seed/save 面板时模式行隐藏，回主菜单又出现
##  5) 截图肉眼确认排版

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _idle(n: int) -> void:
	for _i in n:
		await process_frame


func _btns(box: Node) -> Array:
	var out: Array = []
	for c in box.get_children():
		if c is Button:
			out.append(c)
	return out


func _find_btn(box: Node, sub: String) -> Button:
	for c in _btns(box):
		if String((c as Button).text).contains(sub):
			return c as Button
	return null


func _run() -> void:
	var m: PackedScene = load("res://scenes/menu.tscn")
	var menu := m.instantiate()
	root.add_child(menu)
	await _idle(20)
	chk(menu.is_inside_tree(), "主菜单已进树")

	var mode_box: Node = menu.get("_mode_box")
	chk(mode_box != null, "存在模式行 _mode_box")
	if mode_box == null:
		_done()
		return

	var serious := _find_btn(mode_box, "正经")
	var thunder := _find_btn(mode_box, "雷霆")
	chk(serious != null, "模式行里有『正经模式』按钮")
	chk(thunder != null, "模式行里有『雷霆模式』按钮")
	if serious != null:
		chk(bool(serious.disabled), "『正经模式』是禁用态（未制作）")
		chk(String(serious.text).contains("未制作"), "『正经模式』按钮文字标了『未制作』")
	if thunder != null:
		chk(not bool(thunder.disabled), "『雷霆模式』可点击")

	var main_box: Node = menu.get("_main_box")
	chk(main_box != null and _btns(main_box).size() == 4,
		"原主按钮行仍是 4 个（实测 %d）" % (0 if main_box == null else _btns(main_box).size()))

	# 模式行随面板切换显隐
	menu.call("_show", "seed")
	await _idle(2)
	chk(not bool(mode_box.visible), "切到『输入种子』时模式行隐藏")
	menu.call("_show", "main")
	await _idle(2)
	chk(bool(mode_box.visible), "回主菜单时模式行重新出现")

	_snap("menu_modes")
	_done()


func _snap(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		chk(false, "%s：拿不到视口纹理（必须窗口模式跑）" % name)
		return
	img.save_png("user://%s.png" % name)
	print("  截图 | %s.png" % name)


func _done() -> void:
	print("\n== 菜单模式行自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
