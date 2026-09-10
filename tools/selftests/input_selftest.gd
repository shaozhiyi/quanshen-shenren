extends SceneTree
## 窗口模式输入自检：Tab 开/关背包、ESC 关闭、玩家禁用与鼠标模式联动
## （输入检测必须窗口模式 + 真实帧间隔，headless 会把按下/抬起压进同一帧）

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== 背包开关输入自检 ==")
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _press(k: Key) -> void:
	var d := InputEventKey.new()
	d.keycode = k
	d.pressed = true
	Input.parse_input_event(d)
	await _frames(4)          # 按下与抬起之间留真实帧距
	var u := InputEventKey.new()
	u.keycode = k
	u.pressed = false
	Input.parse_input_event(u)
	await _frames(6)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	w.get_node("Ground").set("seed_value", 777)
	root.add_child(w)
	await _frames(40)

	var inv := w.get_node("HUD/Inventory")
	var player := w.get_node("Player")

	chk(not bool(inv.get("_open")), "初始：背包关闭")
	chk(not bool(inv.visible), "初始：面板不可见")

	await _press(KEY_TAB)
	chk(bool(inv.get("_open")), "第一次按 Tab → 打开（此前无反应的 bug 已修）")
	chk(bool(inv.visible), "面板已显示")
	chk(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "打开后鼠标解绑可点 UI")
	chk(player.process_mode == Node.PROCESS_MODE_DISABLED, "打开后玩家被禁用（不会误触 E 进空间）")
	var img := root.get_texture().get_image()
	img.save_png("user://shots/inventory_open.png")

	await _press(KEY_TAB)
	chk(not bool(inv.get("_open")), "再按 Tab → 关闭")
	chk(not bool(inv.visible), "面板已隐藏")
	chk(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "关闭后鼠标重新捕获")
	chk(player.process_mode != Node.PROCESS_MODE_DISABLED, "关闭后玩家恢复操作")

	# 开着面板按 ESC 也应能关闭
	await _press(KEY_TAB)
	chk(bool(inv.get("_open")), "第三次 Tab → 再次打开")
	await _press(KEY_ESCAPE)
	chk(not bool(inv.get("_open")), "面板打开时按 ESC → 关闭（不会卡住鼠标）")

	# 连续快速开关不应错乱
	await _press(KEY_TAB)
	await _press(KEY_TAB)
	await _press(KEY_TAB)
	chk(bool(inv.get("_open")), "奇数次 Tab 后为打开状态")
	await _press(KEY_TAB)

	# 打开状态下的 E 丢弃：先选中一把武器再按 E
	await _press(KEY_TAB)
	var before_eq: String = inv.call("eq_get", "weapon")
	inv.call("select_slot", ["eq", "weapon"])
	await _press(KEY_E)
	var after_eq: String = inv.call("eq_get", "weapon")
	chk(before_eq == "sword" and after_eq == "", "打开面板选中武器后按 E 丢弃生效（装备栏已空）")
	var boxes := w.get_tree().get_nodes_in_group("drop_box") if w.get_tree() != null else []
	chk(boxes.size() >= 1, "地上生成了掉落箱")
	await _press(KEY_TAB)

	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
