extends SceneTree
## 名册驱动的 BOSS 自检（对任意 BOSS 数量都适用）+ 防具 ×0.7 向下取整
## 覆盖：每只的数值确实来自名册、落点约束、目标选择、逐只独立难度、
##       可重复挑战（复活/满血）、掉落累计、防具取整与零头累计

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== 名册 BOSS 自检 ==")
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	w.get_node("Ground").set("seed_value", 90210)
	root.add_child(w)
	await _frames(8)

	var player := w.get_node("Player")
	var inv := w.get_node("HUD/Inventory")
	var ground := w.get_node("Ground")
	var roster = load("res://scripts/boss_roster.gd")
	var bosses: Array = player.call("bosses")

	chk(bosses.size() == roster.ids().size(), "场上 BOSS 数量 = 名册条目数（%d/%d）" % [bosses.size(), roster.ids().size()])

	# 每只的数值与名册一致 + 落点合规
	for b in bosses:
		var id := String(b.get("def_id"))
		var d: Dictionary = roster.def(id)
		var nm := String(b.get("boss_name"))
		chk(nm == String(d.get("name")), "%s：显示名取自名册" % nm)
		var hbd: Array = d.get("hp_by_diff", [])
		var want_hp: float = float(hbd[0]) if hbd.size() > 0 else float(d.get("base_hp", b.get("max_hp")))
		chk(abs(float(b.get("max_hp")) - want_hp) < 0.01,
			"%s：普通档血量 %d = 名册值" % [nm, int(b.get("max_hp"))])
		chk(abs(float(b.call("aura_damage")) - float(d.get("aura", b.call("aura_damage")))) < 1e-6,
			"%s：光环 %.2f/跳 = 名册值（未开战也生效）" % [nm, float(b.call("aura_damage"))])
		chk(abs(float(b.get("scale_factor")) - float(d.get("scale", b.get("scale_factor")))) < 1e-6, "%s：缩放来自名册" % nm)
		chk(String(b.call("get_reward_item")) == String(d.get("reward")), "%s：掉落物品取自名册" % nm)
		var bp: Vector3 = b.get("position")
		var hd := Vector2(bp.x - player.global_position.x, bp.z - player.global_position.z).length()
		var band: Array = d.get("band")
		chk(hd >= float(band[0]) - 0.5 and hd <= float(band[1]) + 0.5,
			"%s：落点 %.1f 米，在名册 %d~%d 带内" % [nm, hd, int(band[0]), int(band[1])])
		chk(float(ground.call("normal_at", bp.x, bp.z).y) >= 0.93, "%s：落点坡度平缓" % nm)
		chk(abs(bp.y - float(ground.call("height_at", bp.x, bp.z))) < 0.01, "%s：精确贴地" % nm)

	for i in bosses.size():
		for j in range(i + 1, bosses.size()):
			var p0: Vector3 = bosses[i].get("position")
			var p1: Vector3 = bosses[j].get("position")
			chk(Vector2(p0.x - p1.x, p0.z - p1.z).length() >= 29.0, "两只 BOSS 不挤在一起")

	# ---- 目标选择 + 第一只的完整难度流程 ----
	var milk: Node = bosses[0]
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0, milk.global_position.z + 8.0)
	chk(player.call("current_boss") == milk, "站到它旁边 → 交互目标就是它")
	chk(not milk.call("can_adjust_difficulty"), "未击败过 → 难度锁定")
	player._enter_arena()
	chk(player.in_arena() and bool(milk.call("is_arena_mode")), "进入空间后只有被挑战的那只可被伤害")
	var g := 0
	while milk.hp > 0.0 and g < 300:
		milk.take_damage(50)
		g += 1
	chk(milk.is_dead(), "%s 被击杀" % milk.get("boss_name"))
	var want := int(milk.call("reward_count"))
	chk(inv.call("count_of", String(milk.call("get_reward_item"))) == want,
		"普通档到账 %d 个掉落物" % want)
	player._exit_arena()
	chk(not milk.is_dead() and abs(milk.hp - milk.max_hp) < 0.01, "离场后原地复活满血（可重复挑战）")
	chk(milk.call("can_adjust_difficulty"), "击败一次后解锁难度")
	milk.call("cycle_difficulty")
	chk(milk.difficulty == 1 and abs(milk.max_hp - float(roster.def(String(milk.get("def_id"))).get("base_hp")) * 1.6) < 0.01,
		"困难档血量 = 名册基准 ×1.6")
	chk(abs(milk.call("aura_damage") - float(roster.def(String(milk.get("def_id"))).get("aura")) * 1.5) < 1e-6,
		"困难档光环 = 名册基准 ×1.5")
	milk.call("cycle_difficulty")
	milk.call("cycle_difficulty")
	chk(milk.difficulty == 0, "三档循环回普通")

	# ---- 撤退重置 ----
	player._enter_arena()
	milk.take_damage(300)
	player._exit_arena()
	chk(abs(milk.hp - milk.max_hp) < 0.01, "中途撤退 → BOSS 回满血")

	# ---- 防具 ×0.7 向下取整 ----
	var free_slot := -1
	for i in 27:
		if String(inv.call("bag_get", i)) == "":
			free_slot = i
			break
	inv.call("move_item", ["eq", "armor"], ["bag", free_slot])
	await _frames(2)
	chk(abs(float(player.get("armor_factor")) - 1.0) < 1e-6, "脱甲后 armor_factor=1.0")
	player.hp = 100.0
	player.call("take_damage", 10.0)
	chk(abs(player.hp - 90.0) < 1e-6, "无甲：10 点照扣")
	player.call("take_damage", 0.3)
	chk(abs(player.hp - 89.7) < 1e-6, "无甲：0.3/跳按小数扣")
	inv.call("move_item", ["bag", free_slot], ["eq", "armor"])
	await _frames(2)
	chk(abs(float(player.get("armor_factor")) - 0.7) < 1e-6, "穿甲后 armor_factor=0.7")
	player.hp = 100.0
	player.call("take_damage", 10.0)
	chk(abs(player.hp - 93.0) < 1e-6, "有甲：10 → 7（向下取整）")
	player.call("take_damage", 1.0)
	chk(abs(player.hp - 93.0) < 1e-6, "有甲：1 → 0.7 取整为 0，零头先攒着")
	for i in 4:
		player.call("take_damage", 0.3)
	chk(abs(player.hp - 92.0) < 1e-6, "有甲：零头累计满 1 点才扣（0.7+0.84=1.54）")
	player.hp = 100.0
	for i in 20:
		player.call("take_damage", 1.0)
	chk(abs(player.hp - 86.0) < 1e-6, "有甲：20 次 1 点 → 实扣 14")
	player.hp = 1.0
	player.call("take_damage", 2.0)
	chk(abs(player.hp - 30.0) < 1e-6, "有甲也会被打死 → 30% 血复活")

	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
