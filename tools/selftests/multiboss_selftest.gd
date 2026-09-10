extends SceneTree
## 多 BOSS + 防具新规则的无头自检
## 覆盖：名册批量生成、各自数值/掉落、最近目标选择、逐只独立难度、
##       可重复挑战（复活/满血）、防具 ×0.7 向下取整（含零头累计）

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== 多 BOSS / 防具自检 ==")
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	w.get_node("Ground").set("seed_value", 4242)
	root.add_child(w)
	await _frames(8)

	var player := w.get_node("Player")
	var inv := w.get_node("HUD/Inventory")
	var roster := load("res://scripts/boss_roster.gd")

	var bosses: Array = player.call("bosses")
	chk(bosses.size() == roster.ids().size(), "名册 %d 只 BOSS 全部生成（实际 %d）" % [roster.ids().size(), bosses.size()])

	# 每只的数值来自自己的名册条目
	var by_name := {}
	for b in bosses:
		by_name[String(b.get("boss_name"))] = b
		print("     %s：HP %d ｜ 光环 %.2f/跳 ｜ 掉落 %s×%d ｜ 距离带 %d~%d" % [
			b.get("boss_name"), int(b.get("max_hp")), float(b.call("aura_damage")),
			String(b.call("get_reward_item")), int(b.call("reward_count")),
			int(b.get("spawn_min_dist")), int(b.get("spawn_max_dist"))])
	# 逐条对照名册：名字、基准血量、掉落物都应来自 DEFS（增删条目无需改本测试）
	for id in roster.ids():
		var d: Dictionary = roster.def(String(id))
		var nm := String(d["name"])
		var b: Node = by_name.get(nm)
		chk(b != null, "名册 %s（%s）已生成" % [nm, String(id)])
		if b == null:
			continue
		var _hbd: Array = d.get("hp_by_diff", [])
		var _want_base: float = float(_hbd[0]) if _hbd.size() > 0 else float(d.get("base_hp", 0.0))
		chk(abs(float(b.get("_base_max_hp")) - _want_base) < 0.01,
			"%s 基准血量取自名册（%d）" % [nm, int(_want_base)])
		chk(String(b.call("get_reward_item")) == String(d["reward"]),
			"%s 掉落物取自名册（%s）" % [nm, String(d["reward"])])
		chk(int(b.get("spawn_min_dist")) == int(d["band"][0]) and int(b.get("spawn_max_dist")) == int(d["band"][1]),
			"%s 出生距离带取自名册（%d~%d 米）" % [nm, int(d["band"][0]), int(d["band"][1])])
	var milk: Node = by_name.get("野生狗奶")
	chk(milk != null, "名册里的主角野生狗奶在场上")
	chk(abs(float(milk.get("max_hp")) - 1000.0) < 0.01, "野生狗奶 普通档 1000 血")

	# ---- 交互目标 = 最近的那只 ----
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0, milk.global_position.z + 8.0)
	var tgt: Node = player.call("current_boss")
	chk(tgt == milk, "站在野生狗奶旁 → 目标就是它")
	player._enter_arena()
	chk(player.in_arena() and String(player.call("current_boss").get("boss_name")) == "野生狗奶", "进的是野生狗奶的空间")
	chk(milk.is_arena_mode(), "被挑战的那只进入可伤害状态")

	# ---- 击杀：按该只该档掉落（狗奶 ×2 ＋ 强化石 ≥1）；难度逐只独立 ----
	var milk0 := int(inv.call("count_of", "dogmilk"))
	var stone0 := int(inv.call("count_of", "stone"))
	var g := 0
	while milk.hp > 0.0 and g < 200:
		milk.take_damage(50)
		g += 1
	chk(milk.is_dead(), "野生狗奶被击杀")
	chk(int(inv.call("count_of", "dogmilk")) - milk0 == 2, "普通档到账狗奶 ×2")
	chk(int(inv.call("count_of", "stone")) - stone0 >= 1, "击杀必掉强化石（本次 +%d）" % (int(inv.call("count_of", "stone")) - stone0))
	chk(int(milk.call("times_beaten")) == 1, "击败计数=1")
	player._exit_arena()
	chk(not milk.is_dead() and abs(milk.hp - 1000.0) < 0.01, "离场后原地复活满血（可重复挑战）")
	chk(milk.call("can_adjust_difficulty"), "击败一次后解锁难度调节")
	milk.call("cycle_difficulty")
	chk(int(milk.get("difficulty")) == 1 and abs(milk.max_hp - 1600.0) < 0.01, "困难档 1600 血（1000×1.6）")
	chk(int(milk.call("reward_count")) == 3, "困难档掉落 ×3")

	# ---- 再打赢一次：按新档位结算 ----
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0, milk.global_position.z + 8.0)
	player._enter_arena()
	chk(abs(milk.hp - 1600.0) < 0.01, "困难档开战满血 1600")
	milk0 = int(inv.call("count_of", "dogmilk"))
	g = 0
	while milk.hp > 0.0 and g < 200:
		milk.take_damage(50)
		g += 1
	player._exit_arena()
	chk(int(inv.call("count_of", "dogmilk")) - milk0 == 3, "困难档再到账狗奶 ×3")
	chk(int(milk.call("times_beaten")) == 2, "击败计数累计=2")

	# ---- 防具：受到伤害 ×0.7 向下取整，零头累计 ----
	var free_slot := -1
	for i in 27:
		if String(inv.call("bag_get", i)) == "":
			free_slot = i
			break
	chk(free_slot >= 0, "找到空背包格 %d 用于暂存防具" % free_slot)
	inv.call("move_item", ["eq", "armor"], ["bag", free_slot])   # 先脱甲
	await _frames(2)
	chk(abs(float(player.get("armor_factor")) - 1.0) < 1e-6, "脱甲后 armor_factor=1.0")
	player.hp = 100.0
	player.call("take_damage", 10.0)
	chk(abs(player.hp - 90.0) < 1e-6, "无甲：10 点伤害照扣（hp=%.1f）" % player.hp)
	player.call("take_damage", 0.3)
	chk(abs(player.hp - 89.7) < 1e-6, "无甲：光环 0.3/跳按小数扣（hp=%.2f）" % player.hp)

	inv.call("move_item", ["bag", free_slot], ["eq", "armor"])   # 再穿甲
	await _frames(2)
	chk(abs(float(player.get("armor_factor")) - 0.7) < 1e-6, "穿甲后 armor_factor=0.7")
	player.hp = 100.0
	player.call("take_damage", 10.0)
	chk(abs(player.hp - 93.0) < 1e-6, "有甲：10 → 7（向下取整），hp=%.1f" % player.hp)
	player.call("take_damage", 1.0)
	chk(abs(player.hp - 93.0) < 1e-6, "有甲：1 → 0.7 取整为 0，这点伤害先不扣（hp=%.1f）" % player.hp)
	for i in 4:
		player.call("take_damage", 0.3)
	chk(abs(player.hp - 92.0) < 1e-6, "有甲：再 4 跳 0.3（0.7+0.84=1.54）累计扣满 1 点，hp=%.1f" % player.hp)
	player.hp = 100.0
	for i in 20:
		player.call("take_damage", 1.0)
	chk(abs(player.hp - 86.0) < 1e-6, "有甲：20 次 1 点 → 实扣 14（×0.7 取整累计），hp=%.1f" % player.hp)
	player.hp = 1.0
	player.call("take_damage", 2.0)
	chk(abs(player.hp - 30.0) < 1e-6, "有甲也会被击杀：血尽后按 30%% 复活（hp=%.1f）" % player.hp)

	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
