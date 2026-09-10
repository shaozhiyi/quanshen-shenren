extends SceneTree
## 联机背包自检：真实 PvpPlayer + pvp_hud + 背包，开包后核对面板是否真的居中在屏幕上
## （曾经的 bug：背包面板用 (size - panel.size)*0.5 定位，联机里 size=0 → 面板跑到左上角外）

const SHOT := "user://pvp_inv_open.png"


func _idle(n: int) -> void:
	for _i in n:
		await physics_frame


func _initialize() -> void:
	_run()


func _find_panel(n: Node) -> Panel:
	for c in n.get_children():
		if c is Panel:
			return c as Panel
		var r := _find_panel(c)
		if r != null:
			return r
	return null


func _run() -> void:
	var fails := [0]
	var chk := func(ok: bool, tag: String) -> void:
		if ok:
			print("  ok  | ", tag)
		else:
			fails[0] += 1
			print("  FAIL| ", tag)

	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2, 4)
	cam.look_at(Vector3(0, 1, 0), Vector3.UP)
	world.add_child(cam)
	cam.current = true

	var player: CharacterBody3D = (load("res://scripts/pvp/pvp_player.gd") as GDScript).new()
	player.setup(1, "玩家1", Vector3.ZERO)
	world.add_child(player)
	await _idle(5)

	var hud := CanvasLayer.new()
	hud.set_script(load("res://scripts/pvp/pvp_hud.gd"))
	root.add_child(hud)
	await _idle(5)
	hud.call("bind", player)
	await _idle(10)

	var inv: Control = hud.get_node_or_null("Inventory")
	chk.call(inv != null, "联机 HUD 里有背包节点")
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = true
	inv.get_viewport().push_input(ev)      # 走真实输入链路开包
	await _idle(6)
	chk.call(bool(inv.visible), "Tab 能在联机里打开背包")

	var panel := _find_panel(inv)
	chk.call(panel != null, "背包面板存在")
	if panel != null:
		var vs := root.get_visible_rect().size
		var want := Vector2((vs.x - 838.0) * 0.5, (vs.y - 340.0) * 0.5)
		var got: Vector2 = panel.global_position
		chk.call(got.distance_to(want) < 6.0,
			"面板居中在屏幕中央（实际 %s，期望 %s）" % [str(got.round()), str(want.round())])
		chk.call(got.x >= 0.0 and got.y >= 0.0, "面板没有跑到屏幕外（左上角不再被切掉）")
	# 背包内容：联机初始应为 剑+弓已装备、法杖与狗奶在包里
	var bag: Variant = inv.get("_bag_ids")
	if bag == null:
		bag = inv.get("_bag")
	chk.call(bag != null, "背包数据结构可读（%s）" % str(bag))
	root.get_viewport().get_texture().get_image().save_png(SHOT)
	print("SHOT:", SHOT)
	print("== 联机背包自检：", "0 项失败 ==" if fails[0] == 0 else "%d 项失败 ==" % fails[0])
	quit(0 if fails[0] == 0 else 1)
