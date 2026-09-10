extends SceneTree
## BOSS 难度 / 可重复挑战 / 掉落收益 的无头自检（不污染项目目录，跑完即退出）

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== BOSS 难度系统自检 ==")
	_run()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var world := scene.instantiate()
	world.get_node("Ground").set("seed_value", 161803)
	root.add_child(world)
	for _i in 8:
		await physics_frame

	var boss := get_first_node_in_group("boss_unit")   # BOSS 由 BossField 按名册动态生成
	var player := world.get_node("Player")
	var inv := world.get_node("HUD/Inventory")
	chk(boss != null, "名册 BOSS 已由 BossField 生成")

	# ---- 初始状态：普通档 ----
	chk(boss.difficulty == 0, "初始难度=普通")
	chk(abs(boss.max_hp - 1000.0) < 0.01, "普通档 HP=1000（实际 %f）" % boss.max_hp)
	chk(abs(boss.aura_damage() - 0.3) < 1e-6, "普通档光环 0.3/跳")
	chk(boss.reward_count() == 2, "普通档掉落×2")
	chk(not boss.can_adjust_difficulty(), "未击败过 → 难度锁定不可调")

	# ---- 大地图不可直接攻击 ----
	boss.take_damage(500)
	chk(abs(boss.hp - 1000.0) < 0.01, "大地图上 BOSS 无敌（hp 未变）")

	# ---- 第一次挑战：进空间、击杀、发奖 ----
	player.global_position = Vector3(boss.global_position.x, boss.global_position.y + 1.0, boss.global_position.z + 8.0)
	player._enter_arena()
	chk(player.in_arena(), "按 E 进入 BOSS 空间")
	chk(abs(boss.hp - boss.max_hp) < 0.01, "开战即满血")
	chk(boss.is_arena_mode(), "BOSS 进入可伤害状态")
	var g := 0
	while boss.hp > 0.0 and g < 200:
		boss.take_damage(50)
		g += 1
	chk(boss.is_dead(), "血量清零 → BOSS 被击杀")
	chk(boss.times_beaten() == 1, "击败计数=1")
	chk(inv.count_of("dogmilk") == 2, "普通档到账狗奶×2（实际 %d）" % inv.count_of("dogmilk"))

	# ---- 离开空间 → 原地复活，可再次挑战 ----
	player._exit_arena()
	chk(not player.in_arena(), "离开空间回到大地图")
	chk(not boss.is_dead(), "离场后 BOSS 已复活（可重复挑战）")
	chk(abs(boss.hp - boss.max_hp) < 0.01, "复活即满血")
	chk(boss.position.distance_to(boss.get("_home_pos")) < 0.01, "复活回到大地图原位")
	chk(boss.can_adjust_difficulty(), "击败一次后解锁难度调节")

	# ---- 难度逐级递增：血量 / 伤害 / 收益 ----
	boss.cycle_difficulty()
	chk(boss.difficulty == 1, "R → 困难")
	chk(abs(boss.max_hp - 1600.0) < 0.01, "困难档 HP=1600（实际 %f）" % boss.max_hp)
	chk(abs(boss.aura_damage() - 0.45) < 1e-6, "困难档光环 0.45/跳（×1.5）")
	chk(boss.reward_count() == 3, "困难档掉落×3")
	boss.cycle_difficulty()
	chk(boss.difficulty == 2, "R → 噩梦")
	chk(abs(boss.max_hp - 2400.0) < 0.01, "噩梦档 HP=2400（实际 %f）" % boss.max_hp)
	chk(abs(boss.aura_damage() - 0.6) < 1e-6, "噩梦档光环 0.6/跳（×2.0）")
	chk(boss.reward_count() == 4, "噩梦档掉落×4")

	# ---- 高难度下再打赢一次，收益按档位结算 ----
	player.global_position = Vector3(boss.global_position.x, boss.global_position.y + 1.0, boss.global_position.z + 8.0)
	player._enter_arena()
	chk(abs(boss.hp - 2400.0) < 0.01, "噩梦档开战满血 2400")
	g = 0
	while boss.hp > 0.0 and g < 200:
		boss.take_damage(50)
		g += 1
	chk(boss.is_dead(), "噩梦档可被击杀")
	player._exit_arena()
	chk(inv.count_of("dogmilk") == 6, "噩梦档额外到账 → 累计狗奶×6（实际 %d）" % inv.count_of("dogmilk"))
	chk(boss.times_beaten() == 2, "击败计数=2")

	# ---- 三档循环回普通；战斗中不可调难度 ----
	boss.cycle_difficulty()
	chk(boss.difficulty == 0, "第三次 R → 循环回普通")
	player.global_position = Vector3(boss.global_position.x, boss.global_position.y + 1.0, boss.global_position.z + 8.0)
	player._enter_arena()
	boss.cycle_difficulty()
	chk(boss.difficulty == 0, "战斗中 R 无效（难度不变）")
	# ---- 中途撤退：BOSS 满血重置 ----
	boss.take_damage(300)
	chk(abs(boss.hp - 700.0) < 0.01, "撤退前已打掉 300 血")
	player._exit_arena()
	chk(abs(boss.hp - 1000.0) < 0.01, "撤退后 BOSS 回满血（普通 1000）")

	# ---- 玩家阵亡：被弹出空间 + 30% 血苏醒 ----
	player.global_position = Vector3(boss.global_position.x, boss.global_position.y + 1.0, boss.global_position.z + 8.0)
	player._enter_arena()
	player.take_damage(9999.0)
	chk(not player.in_arena(), "玩家阵亡 → 被弹出 BOSS 空间")
	chk(abs(player.hp - 30.0) < 0.01, "阵亡后以 30%% 血苏醒（实际 %f）" % player.hp)
	chk(not boss.is_dead(), "玩家失败不等于 BOSS 死亡")

	# ---- add_item 批量接口 ----
	var n0: int = inv.count_of("dogmilk")
	var ok3: bool = inv.add_item("dogmilk", 3)
	chk(ok3, "一次加入 3 瓶返回成功")
	chk(inv.count_of("dogmilk") == n0 + 3, "批量加入后计数正确（%d → %d）" % [n0, int(inv.count_of("dogmilk"))])
	print("== 结果：%d 项失败 ==\n" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
