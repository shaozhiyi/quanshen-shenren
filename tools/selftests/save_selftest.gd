extends SceneTree
## 存档系统 + 主菜单 的无头集成自检
## 覆盖：save/ 目录与 JSON 读写、菜单指定种子真正决定地形、F5 落盘、
##       读档还原血量/背包/BOSS 难度、菜单三按钮与非法种子输入

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== 存档 / 主菜单自检 ==")
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _collect_buttons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button:
			out.append(String(c.text))
		_collect_buttons(c, out)


func _run() -> void:
	# ---- 1. 存档目录与 JSON 读写 ----
	var dir := SaveManager.save_dir()
	chk(DirAccess.dir_exists_absolute(dir), "save/ 目录已创建：%s" % dir)
	var probe := SaveManager.slot_path("_selftest")
	var data := SaveManager.build_data(777, 14.5, 0.0093,
		{"hp": 42.5, "max_hp": 100.0, "x": 1.0, "y": 2.0, "z": 3.0, "yaw": 0.5, "pitch": -0.1, "weapon": 1, "kills": 7},
		{"equipment": {"weapon": "sword", "subweapon": "", "armor": "armor"}, "bag": ["dogmilk", "", "bow"]},
		{"dogmilk": {"difficulty": 2, "beats": 3}}, 7)
	chk(SaveManager.write_to(probe, data), "写入 JSON 成功")
	chk(FileAccess.file_exists(probe), "存档文件真实存在")
	var back := SaveManager.read_from(probe)
	chk(int(back.seed) == 777, "种子读回一致")
	chk(abs(float(back.player.hp) - 42.5) < 1e-6, "血量读回一致")
	chk(String(back.equipment.subweapon) == "", "装备栏读回一致（副武器已卸）")
	chk(String(back.bag[2]) == "bow", "背包第 3 格读回 bow")
	chk(int(back.bosses.dogmilk.difficulty) == 2, "BOSS 难度读回噩梦")
	chk(int(back.version) == 1, "存档带版本号")
	var bad := SaveManager.read_from(dir.path_join("__not_exist__.json"))
	chk(bad.is_empty(), "不存在的文件返回空字典（不崩）")

	# ---- 2. 菜单指定种子 → 真正决定地形 ----
	SaveManager.stage_new_game(777)
	chk(SaveManager.pending_seed == 777 and SaveManager.pending_load.is_empty(), "stage_new_game 只带种子")
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(25)
	var world := current_scene
	chk(world != null and String(world.name).begins_with("Main"), "菜单→游戏场景切换成功")
	var ground := world.get_node("Ground")
	chk(int(ground.get("terrain_seed")) == 777, "地形种子取自菜单（%d）" % int(ground.get("terrain_seed")))
	var player := world.get_node("Player")
	var inv := world.get_node("HUD/Inventory")
	var boss: Node = player.call("bosses")[0]

	# ---- 3. F5 快速存档落盘 ----
	player.hp = 42.5
	player.call("_quick_save")
	var slot := String(SaveManager.current_slot)
	chk(FileAccess.file_exists(slot), "F5 写出当前槽位：%s" % slot.get_file())
	var saved := SaveManager.read_from(slot)
	chk(abs(float(saved.player.hp) - 42.5) < 1e-6, "存档内血量正确")
	chk(int(saved.seed) == 777, "存档内种子正确")
	chk(int(saved.bosses.dogmilk.difficulty) == 0, "存档内 BOSS 为普通档")

	# ---- 4. 改动作后读档，应回到存档时的状态 ----
	inv.call("add_item", "dogmilk", 3)
	boss.set("_beats", 1)
	boss.call("cycle_difficulty")
	player.global_position = Vector3(900.0, 5.0, 900.0)
	chk(int(inv.call("count_of", "dogmilk")) == 3, "读档前背包已有 3 瓶狗奶")
	chk(int(boss.get("difficulty")) == 1, "读档前难度已切到困难")

	SaveManager.stage_load(slot)
	chk(SaveManager.pending_seed == 777 and not SaveManager.pending_load.is_empty(), "stage_load 同时带种子与状态")
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(25)
	world = current_scene
	player = world.get_node("Player")
	inv = world.get_node("HUD/Inventory")
	boss = player.call("bosses")[0]
	chk(abs(player.hp - 42.5) < 1e-6, "读档还原血量 42.5（实际 %.1f）" % player.hp)
	chk(int(inv.call("count_of", "dogmilk")) == 0, "读档还原背包（狗奶回到存档时的 0 瓶）")
	chk(int(boss.get("difficulty")) == 0, "读档还原 BOSS 难度为普通")
	chk(abs(float(boss.get("max_hp")) - 1000.0) < 0.01, "难度还原后血量上限同步回 1000")
	chk(int(boss.call("times_beaten")) == 0, "击败次数也按存档还原")
	chk(abs(player.global_position.x - float(saved.player.x)) < 0.01, "读档还原玩家坐标")
	chk(int(world.get_node("Ground").get("terrain_seed")) == 777, "读档后地形按存档种子重建")

	# ---- 5. 存档列表 ----
	var list := SaveManager.list_saves()
	chk(list.size() >= 2, "list_saves 找到 %d 个存档" % list.size())
	chk(SaveManager.describe(list[0]).length() > 6, "摘要文本：%s" % SaveManager.describe(list[0]))

	# ---- 6. 主菜单场景 ----
	change_scene_to_file("res://scenes/menu.tscn")
	await _frames(15)
	var menu := current_scene
	chk(menu != null, "主菜单场景可加载")
	var names: Array = []
	_collect_buttons(menu, names)
	chk(names.has("新游戏") and names.has("读取存档") and names.has("输入种子"),
		"三个主按钮齐全：%s" % str(names))
	chk(not bool(menu.get("_seed_box").visible) and not bool(menu.get("_save_box").visible),
		"子面板默认隐藏")

	# 非法种子输入：不应切场景
	var edit: LineEdit = menu.get("_seed_edit")
	menu.call("_show", "seed")
	edit.text = "abc"
	menu.call("_on_seed_start")
	await _frames(3)
	chk(current_scene == menu, "非法种子不会进入游戏")
	chk(String(menu.get("_status").text).find("整数") >= 0, "非法种子给出提示：%s" % String(menu.get("_status").text))

	# 读取存档面板能列出条目
	menu.call("_show", "save")
	await _frames(3)
	var save_names: Array = []
	_collect_buttons(menu, save_names)
	var has_entry := false
	for n in save_names:
		if String(n).find("种子") >= 0:
			has_entry = true
	chk(has_entry, "读取存档面板列出了存档条目")

	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
