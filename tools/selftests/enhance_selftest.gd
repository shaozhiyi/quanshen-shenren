extends SceneTree
## 逐件装备强化（双击哪件强化哪件 + 消耗强化石）/ 掉落概率 / 堆叠 —— 无头自检

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== 逐件强化 / 掉落概率自检 ==")
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


func _first_bag_slot(inv: Node, id: String) -> int:
	for i in 27:
		if String(inv.call("bag_get", i)) == id:
			return i
	return -1


func _lv(player: Node, id: String) -> int:
	return int(player.call("enhance_level_of", id))


func _run() -> void:
	var w := _make_world()
	await _frames(8)
	var player := w.get_node("Player")
	var inv := w.get_node("HUD/Inventory")
	var boss: Node = player.call("bosses")[0]

	# ---- 1. 追加掉落概率调成原来的 5%：80%→4%、79%→3.95%… ----
	var trials := 20000
	var total := 0
	var mn := 999
	var mx := 0
	var extra := 0
	for i in trials:
		var s := int(player.call("_roll_stones"))
		mn = mini(mn, s)
		mx = maxi(mx, s)
		total += s
		if s > 1:
			extra += 1
	var mean := float(total) / float(trials)
	var rate := float(extra) / float(trials)
	chk(mn == 1, "仍然必掉 1 块（最小 %d）" % mn)
	chk(mean > 1.03 and mean < 1.055, "期望 %.4f ≈ 理论 1.0418（原来是 4.1）" % mean)
	chk(rate > 0.025 and rate < 0.058, "只有约 %.1f%% 的击杀能多掉（理论 4.0%%）" % [rate * 100.0])
	chk(mx <= 4, "长尾基本被砍掉（本次最多 %d 块）" % mx)

	# ---- 2. 堆叠规则不变 ----
	chk(int(inv.call("stack_max_of", "dogmilk")) == 20, "狗奶每格上限 20")
	inv.call("add_item", "dogmilk", 25)
	chk(int(inv.call("count_of", "dogmilk")) == 25, "一次加 25 瓶 → 总数 25")
	# 起始背包第 0 格是法杖，狗奶从第 1 格开始堆
	var lbl: Label = (inv.get("_bag_slots") as Array)[1].get_meta("count")
	chk(lbl.text == "×20" and lbl.visible, "第 2 格显示 ×20")
	chk(int(inv.call("bag_count", 2)) == 5, "溢出 5 瓶另起一格 ×5")

	# ---- 3. 双击剑 → 只有剑升级，且只吃 1 块石头 ----
	inv.call("add_item", "stone", 5)
	chk(int(inv.call("count_of", "stone")) == 5, "先放 5 块强化石")
	for i in 3:
		inv.call("use_slot", ["eq", "weapon"])
	chk(_lv(player, "sword") == 3, "双击剑 3 次 → 剑 +3（实际 +%d）" % _lv(player, "sword"))
	chk(_lv(player, "bow") == 0, "弓没被牵连 → 仍 +0")
	chk(_lv(player, "armor") == 0, "防具没被牵连 → 仍 +0")
	chk(int(inv.call("count_of", "stone")) == 2, "只消耗 3 块（剩 %d）" % int(inv.call("count_of", "stone")))
	chk(abs(float(player.call("damage_scale_for", "sword")) - 1.331) < 1e-4, "剑倍率 ×1.331（1.1³，指数级）")
	chk(abs(float(player.call("damage_scale_for", "bow")) - 1.0) < 1e-6, "弓倍率仍 ×1.00（不吃剑的等级）")
	chk(abs(float(player.armor_factor) - 0.7) < 1e-6, "防具未强化 → 受伤仍 ×0.70")

	# ---- 4. 弓的伤害只认弓自己的等级 ----
	var bow := w.get_node("Player/Camera3D/Bow")
	chk(abs(float(bow.call("_player_damage_scale")) - 1.0) < 1e-6, "弓取倍率 = 弓的 +0 → ×1.00")
	inv.call("use_slot", ["eq", "subweapon"])
	chk(_lv(player, "bow") == 1 and _lv(player, "sword") == 3, "双击弓 → 只有弓 +1（剑仍 +3）")
	chk(abs(float(bow.call("_player_damage_scale")) - 1.1) < 1e-6, "之后弓才吃到 ×1.10")
	chk(abs(float(player.call("damage_scale_for", "sword")) - 1.331) < 1e-4, "剑倍率不受影响 ×1.331")
	chk(int(inv.call("count_of", "stone")) == 1, "累计消耗 4 块，剩 %d" % int(inv.call("count_of", "stone")))

	# ---- 5. 双击防具 → 减伤跟着防具等级走 ----
	inv.call("use_slot", ["eq", "armor"])
	chk(_lv(player, "armor") == 1, "防具 +1")
	chk(abs(float(player.armor_factor) - 0.67) < 1e-6, "受伤 ×0.70 → ×0.67（每级再 -3%）")
	chk(_lv(player, "sword") == 3 and _lv(player, "bow") == 1, "武器等级不受影响")
	chk(int(inv.call("count_of", "stone")) == 0, "石头用尽（剩 %d）" % int(inv.call("count_of", "stone")))

	# ---- 6. 没石头时双击武器：不升级、不吞东西 ----
	var lv_before := _lv(player, "sword")
	inv.call("use_slot", ["eq", "weapon"])
	chk(_lv(player, "sword") == lv_before, "无石头时双击剑不升级")

	# ---- 7. 双击强化石本身：不消耗 ----
	inv.call("add_item", "stone", 2)
	var stones_before := int(inv.call("count_of", "stone"))
	var stone_slot := _first_bag_slot(inv, "stone")
	inv.call("use_slot", ["bag", stone_slot])
	chk(int(inv.call("count_of", "stone")) == stones_before, "双击石头只是查看，不消耗（仍 %d）" % stones_before)
	chk(_lv(player, "sword") == lv_before, "双击石头不再强化任何东西")

	# ---- 8. 封顶 +10：满级后不吃石头（现在点的是装备格，不是石头格） ----
	inv.call("add_item", "stone", 15)
	for i in 12:
		inv.call("use_slot", ["eq", "weapon"])
	chk(_lv(player, "sword") == 10, "双击剑 12 次 → 封顶 +10（实际 +%d）" % _lv(player, "sword"))
	chk(_lv(player, "armor") == 1 and _lv(player, "bow") == 1, "封顶只封这一件，别的照样低（甲 +%d 弓 +%d）" % [
		_lv(player, "armor"), _lv(player, "bow")])
	chk(int(inv.call("count_of", "stone")) == 10, "从 +3 到 +10 正好吃 7 块（剩 %d）" % int(inv.call("count_of", "stone")))
	var keep := int(inv.call("count_of", "stone"))
	inv.call("use_slot", ["eq", "weapon"])
	chk(_lv(player, "sword") == 10, "满级再点不提升")
	chk(int(inv.call("count_of", "stone")) == keep, "满级时不吃石头（仍 %d 块）" % keep)
	chk(abs(float(player.call("damage_scale_for", "sword")) - 2.5937424601) < 1e-6, "剑满级倍率 ×2.5937（1.1¹⁰，攻击 50→129）")

	# ---- 9. 背包里的装备：照样能双击强化，格子上显示自己的 +N ----
	inv.call("move_item", ["eq", "subweapon"], ["bag", 10])   # 把 +1 的弓挪进背包
	var bow_enh: Label = (inv.get("_bag_slots") as Array)[10].get_meta("enh")
	chk(bow_enh.visible and bow_enh.text == "+1", "背包里的弓显示 +1（%s）" % bow_enh.text)
	inv.call("use_slot", ["bag", 10])
	chk(_lv(player, "bow") == 2, "在背包里双击弓 → 弓 +2（剑仍 +%d）" % _lv(player, "sword"))
	chk(int(inv.call("count_of", "stone")) == keep - 1, "同样只吃 1 块（剩 %d）" % int(inv.call("count_of", "stone")))
	inv.call("move_item", ["bag", 10], ["eq", "subweapon"])
	inv.call("move_item", ["eq", "weapon"], ["bag", 9])       # 把 +10 的剑挪进背包
	var eq_enh: Label = (inv.get("_eq_slots") as Dictionary)["weapon"].get_meta("enh")
	chk(not eq_enh.visible, "武器栏空了 → 不显示 +N")
	var bag_enh: Label = (inv.get("_bag_slots") as Array)[9].get_meta("enh")
	chk(bag_enh.visible and bag_enh.text == "+10", "背包里的剑显示 +10（%s）" % bag_enh.text)
	var tip := String((inv.get("_bag_slots") as Array)[9].tooltip_text)
	chk(tip.contains("当前 +10 / 10"), "悬浮提示带等级上限（%s）" % tip.replace("\n", " / "))
	var keep2 := int(inv.call("count_of", "stone"))
	inv.call("use_slot", ["bag", 9])
	chk(_lv(player, "sword") == 10 and int(inv.call("count_of", "stone")) == keep2, "满级装备在背包里点也不吞石头")
	inv.call("move_item", ["bag", 9], ["eq", "weapon"])

	# ---- 10. 击杀仍必掉强化石 ----
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
	chk(d_stones >= 1, "击杀后至少到手 1 块（本次 %d）" % d_stones)
	chk(d_milk == 2, "狗奶仍按档位掉 ×%d" % d_milk)
	player._exit_arena()

	# ---- 11. 逐件等级能存能读 ----
	player.hp = 66.0
	player.call("_quick_save")
	var slot := String(SaveManager.current_slot)
	var want_stone := int(inv.call("count_of", "stone"))
	var want_milk := int(inv.call("count_of", "dogmilk"))
	var lvs := [_lv(player, "sword"), _lv(player, "bow"), _lv(player, "armor")]
	print("     存档前：石 %d / 奶 %d / 剑+%d 弓+%d 甲+%d ｜ %s" % [
		want_stone, want_milk, lvs[0], lvs[1], lvs[2], slot.get_file()])
	w.queue_free()
	await _frames(6)
	SaveManager.stage_load(slot)
	var w2 := _make_world()
	await _frames(8)
	var inv2 := w2.get_node("HUD/Inventory")
	var player2 := w2.get_node("Player")
	var got := [_lv(player2, "sword"), _lv(player2, "bow"), _lv(player2, "armor")]
	print("     读档后：石 %d / 奶 %d / 剑+%d 弓+%d 甲+%d" % [
		int(inv2.call("count_of", "stone")), int(inv2.call("count_of", "dogmilk")), got[0], got[1], got[2]])
	chk(got[0] == lvs[0] and got[1] == lvs[1] and got[2] == lvs[2], "三件等级各自还原（+%d/+%d/+%d）" % lvs)
	chk(abs(float(player2.call("damage_scale_for", "bow")) - pow(1.1, float(lvs[1]))) < 1e-6, "读档后弓倍率按弓的等级恢复（指数级）")
	var want_af := clampf(0.7 - 0.03 * float(lvs[2]), 0.4, 1.0)
	chk(abs(float(player2.armor_factor) - want_af) < 1e-6, "读档后减伤 ×%.2f 按防具等级恢复" % want_af)
	chk(int(inv2.call("count_of", "stone")) == want_stone, "强化石数量一致（×%d）" % want_stone)
	chk(int(inv2.call("count_of", "dogmilk")) == want_milk, "狗奶数量一致（×%d）" % want_milk)
	var cnt_ok := false
	for c2 in inv2.get("_bag_slots"):
		var cl: Label = c2.get_meta("count")
		if cl.visible and cl.text.begins_with("×"):
			cnt_ok = true
	chk(cnt_ok, "读档后仍有一格显示 ×N")
	var eq_lbl: Label = (inv2.get("_eq_slots") as Dictionary)["weapon"].get_meta("enh")
	chk(eq_lbl.visible and eq_lbl.text == "+%d" % lvs[0], "读档后武器栏仍显示 +N（%s）" % eq_lbl.text)

	# ---- 12. 老存档（整数全身等级）也能吃下 ----
	player2.call("_apply_enhance", 4)
	chk(_lv(player2, "sword") == 4 and _lv(player2, "armor") == 4, "老存档 enhance=4 → 三件各按 +4 还原")
	# 字典里没记的那一件 = 那一件回到 +0（老存档没有法杖，不能白留等级）
	player2.call("_apply_enhance", {"sword": 4, "bow": 1, "armor": 2})
	chk(_lv(player2, "sword") == 4 and _lv(player2, "staff") == 0,
		"存档里有的照常还原，没记的（法杖）归零")

	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
