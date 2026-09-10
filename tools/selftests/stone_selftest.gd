extends SceneTree
## 装备强化石 / 堆叠 / 掉落链 的无头自检

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== 强化石 / 堆叠自检 ==")
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _make_world() -> Node:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	w.get_node("Ground").set("seed_value", 271828)
	root.add_child(w)
	return w


func _run() -> void:
	var w := _make_world()
	await _frames(8)
	var player := w.get_node("Player")
	var inv := w.get_node("HUD/Inventory")
	var boss: Node = player.call("bosses")[0]

	# ---- 1. 掉落概率链：必掉1 + 4%/3.95%/3.90%…（原 80% 系列整体 ×0.05）----
	var total := 0
	var trials := 4000
	var mn := 999
	var mx := 0
	for i in trials:
		var s := int(player.call("_roll_stones"))
		mn = mini(mn, s)
		mx = maxi(mx, s)
		total += s
	var mean := float(total) / float(trials)
	chk(mn == 1, "必定至少掉 1 块（最小 %d）" % mn)
	chk(mean > 1.0 and mean < 1.15, "期望值 %.3f ≈ 理论值 1.042（1 + 0.04 + 0.04×0.0395 + …）" % mean)
	chk(mx >= 2, "长尾仍可能连掉（本次最多 %d 块）" % mx)

	# ---- 2. 堆叠：上限 20，超出开新格 ----
	chk(int(inv.call("stack_max_of", "dogmilk")) == 20, "狗奶每格上限 20")
	chk(int(inv.call("stack_max_of", "sword")) == 1, "装备不可堆叠")
	inv.call("add_item", "dogmilk", 25)
	chk(int(inv.call("count_of", "dogmilk")) == 25, "一次加 25 瓶 → 总数 25")
	# 背包第 0 格起始被法杖占着（新增的第三武器），所以狗奶从第 1 格开始堆
	chk(String(inv.call("bag_get", 0)) == "staff", "背包第 1 格起始是法杖")
	chk(String(inv.call("bag_get", 1)) == "dogmilk" and int(inv.call("bag_count", 1)) == 20,
		"第 2 格堆到上限 ×20")
	chk(int(inv.call("bag_count", 2)) == 5, "溢出 5 瓶另起一格")
	var lbl: Label = (inv.get("_bag_slots") as Array)[1].get_meta("count")
	chk(lbl.text == "×20" and lbl.visible, "格子上显示 ×20")
	var lbl1: Label = (inv.get("_bag_slots") as Array)[2].get_meta("count")
	chk(lbl1.text == "×5", "再下一格显示 ×5")
	var tip := String((inv.get("_bag_slots") as Array)[1].tooltip_text)
	chk(tip.contains("×20/20"), "悬浮提示带数量（%s）" % tip.split("\n")[0])

	# ---- 3. 双击石头不消耗；双击装备才吃石头、且只升那一件 ----
	inv.call("add_item", "stone", 3)
	var stone_slot := -1
	for i in 27:
		if String(inv.call("bag_get", i)) == "stone":
			stone_slot = i
			break
	chk(stone_slot >= 0 and int(inv.call("bag_count", stone_slot)) == 3, "强化石堆叠 ×3")
	player.hp = 50.0
	inv.call("use_slot", ["bag", stone_slot])
	chk(int(inv.call("bag_count", stone_slot)) == 3, "双击石头本身不消耗（整堆还在）")
	inv.call("use_slot", ["eq", "weapon"])
	chk(int(inv.call("count_of", "stone")) == 2, "双击「剑」→ 只消耗 1 块")
	chk(int(player.enhance_levels["sword"]) == 1, "剑 +1")
	chk(abs(float(player.call("damage_scale_for", "sword")) - 1.1) < 1e-6, "剑倍率 ×1.10")
	chk(abs(float(player.call("damage_scale_for", "bow")) - 1.0) < 1e-6, "弓不吃剑的等级（仍 ×1.00）")
	chk(abs(float(player.armor_factor) - 0.7) < 1e-6, "防具未强化 → 受伤仍 ×0.70")
	inv.call("use_slot", ["eq", "armor"])
	chk(abs(float(player.armor_factor) - 0.67) < 1e-6, "甲 +1 → 受伤 ×0.67（每级再 -3%）")

	# ---- 4. 升到封顶 +10，满级不再吞石头 ----
	inv.call("add_item", "stone", 12)
	var total0 := int(inv.call("count_of", "stone"))
	var lv0 := int(player.enhance_levels["sword"])
	for i in 12:
		inv.call("use_slot", ["eq", "weapon"])
	chk(int(player.enhance_levels["sword"]) == 10, "强化封顶 +10（实际 +%d）" % int(player.enhance_levels["sword"]))
	chk(int(inv.call("count_of", "stone")) == total0 - (10 - lv0),
		"从 +%d 升到 +10 正好消耗 %d 块（剩 %d）" % [lv0, 10 - lv0, int(inv.call("count_of", "stone"))])
	var keep := int(inv.call("count_of", "stone"))
	inv.call("use_slot", ["eq", "weapon"])
	chk(int(player.enhance_levels["sword"]) == 10, "满级时再点不提升")
	chk(int(inv.call("count_of", "stone")) == keep, "满级时不消耗强化石（仍 %d 块）" % keep)

	# ---- 5. 剑/弓伤害各自只吃自己的等级 ----
	player.enhance_levels["sword"] = 1
	player.enhance_levels["bow"] = 2
	chk(abs(float(player.call("damage_scale_for", "sword")) - 1.1) < 1e-6, "剑 +1 → 倍率 1.10")
	chk(int(roundf(50.0 * float(player.call("damage_scale_for", "sword")))) == 55, "剑：50 → 55")
	chk(int(floor(12.0 * float(player.call("damage_scale_for", "bow")))) == 14, "弓 +2：12 → 14（指数 1.21 后向下取整）")
	var bow := w.get_node("Player/Camera3D/Bow")
	chk(abs(float(bow.call("_player_damage_scale")) - pow(1.1, 2.0)) < 1e-6, "弓取到的是弓自己的强化倍率 ×1.21")

	# ---- 6. 击杀必掉强化石 ----
	var stones0 := int(inv.call("count_of", "stone"))
	var milk0 := int(inv.call("count_of", "dogmilk"))
	player.global_position = Vector3(boss.global_position.x, boss.global_position.y + 1.0, boss.global_position.z + 8.0)
	player._enter_arena()
	var g := 0
	while boss.hp > 0.0 and g < 300:
		boss.take_damage(50)
		g += 1
	var d_stones := int(inv.call("count_of", "stone")) - stones0
	var d_milk := int(inv.call("count_of", "dogmilk")) - milk0
	chk(d_stones >= 1, "击杀后至少到手 1 块强化石（本次 %d）" % d_stones)
	chk(d_milk == 2, "狗奶仍按档位掉落 ×%d" % d_milk)
	player._exit_arena()

	# ---- 7. 丢弃整堆 → 箱子 → 回收 ----
	var s3 := -1
	for i in 27:
		if String(inv.call("bag_get", i)) == "stone":
			s3 = i
			break
	var before := int(inv.call("count_of", "stone"))
	inv.call("select_slot", ["bag", s3])
	inv.call("discard_selected")
	var boxes: Array = w.get_tree().get_nodes_in_group("drop_box")
	chk(boxes.size() == 1, "丢弃后地上出现 1 个箱子")
	chk(int(boxes[0].get("item_count")) == before, "箱子带整堆数量 ×%d" % before)
	player.global_position = Vector3(boxes[0].global_position.x, player.global_position.y, boxes[0].global_position.z)
	inv.call("_toggle")   # 关背包，让 E 走回收分支
	await _frames(2)
	player.call("_try_pick_box")
	chk(int(inv.call("count_of", "stone")) == before, "回收后数量不变（×%d）" % before)
	await _frames(3)
	chk(w.get_tree().get_nodes_in_group("drop_box").size() == 0, "箱子已消失")

	# ---- 8. 堆叠数量能存能读 ----
	player.hp = 66.0
	player.call("_quick_save")
	var slot := String(SaveManager.current_slot)
	var want_stone := int(inv.call("count_of", "stone"))
	var want_milk := int(inv.call("count_of", "dogmilk"))
	var want_lv: Dictionary = (player.enhance_levels as Dictionary).duplicate(true)
	print("     存档前：石 %d / 奶 %d / 强化 %s ｜ 槽位 %s" % [want_stone, want_milk, str(want_lv), slot.get_file()])
	w.queue_free()
	await _frames(6)
	SaveManager.stage_load(slot)
	var w2 := _make_world()
	await _frames(8)
	var inv2 := w2.get_node("HUD/Inventory")
	var player2 := w2.get_node("Player")
	print("     读档后：石 %d / 奶 %d / 强化 %s" % [
		int(inv2.call("count_of", "stone")), int(inv2.call("count_of", "dogmilk")), str(player2.enhance_levels)])
	chk(int(inv2.call("count_of", "stone")) == want_stone, "读档后强化石数量一致（×%d）" % want_stone)
	chk(int(inv2.call("count_of", "dogmilk")) == want_milk, "读档后狗奶数量一致（×%d）" % want_milk)
	var same := true
	for k in ["sword", "bow", "armor"]:
		if int(player2.enhance_levels[k]) != int(want_lv[k]):
			same = false
	chk(same, "读档后每件装备的强化等级逐一一致 %s" % str(want_lv))
	chk(abs(float(player2.call("damage_scale_for", "sword")) - pow(1.1, float(int(want_lv["sword"])))) < 1e-6,
		"读档后剑的攻击力倍率随之恢复（指数级）")
	# 起始背包第 0 格被法杖占着，堆叠数字不一定落在第 0 格 → 扫一遍
	var cnt_ok := false
	for c2 in inv2.get("_bag_slots"):
		var cl: Label = c2.get_meta("count")
		if cl.visible and cl.text.begins_with("×"):
			cnt_ok = true
	chk(cnt_ok, "读档后仍有一格显示 ×N")

	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
