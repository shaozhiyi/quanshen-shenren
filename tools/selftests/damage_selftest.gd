extends SceneTree
## 回归自检：BOSS 攻击期必须真的对玩家造成伤害（此前 ../Player 取到 null 导致零伤害），
## 同时验证日月交替驱动与"正面朝向玩家"也恢复。
## 做法：绕开 _process，直接按固定 delta 喂 _update_windup()（最可靠的相位驱动方式）。

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== 光环伤害回归自检 ==")
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	w.get_node("Ground").set("seed_value", 555)
	root.add_child(w)
	await _frames(8)

	var player := w.get_node("Player")
	var inv := w.get_node("HUD/Inventory")
	var boss: Node = player.call("bosses")[0]

	# 根因检查：三个跨层级查找都必须拿得到节点
	chk(boss.call("player_node") == player, "BOSS 能找到玩家（按分组，不再依赖 ../Player）")
	chk(boss.call("arena_node") == w.get_node("Arena"), "BOSS 能找到竞技场")
	chk(boss.call("ground_node") == w.get_node("Ground"), "BOSS 能找到地形")

	# 进入空间
	player.global_position = Vector3(boss.global_position.x, boss.global_position.y + 1.0, boss.global_position.z + 8.0)
	player._enter_arena()
	chk(player.in_arena(), "已进入 BOSS 空间")

	# ---- 无甲：攻击期应掉 0.3/跳 ----
	var free_slot := -1
	for i in 27:
		if String(inv.call("bag_get", i)) == "":
			free_slot = i
			break
	inv.call("move_item", ["eq", "armor"], ["bag", free_slot])
	await _frames(2)
	player.hp = 100.0
	boss.set("_phase", 2)
	boss.set("_phase_t", 0.0)
	boss.set("_stars_fired", 24)   # 本段只测光环伤害，不让星点参进来
	boss.set("_dmg_t", 0.0)
	for i in 20:
		boss.call("_update_windup", 0.1)
	chk(abs(player.hp - 94.0) < 1e-6, "无甲：2 秒攻击期掉 6 血（0.3/跳×20），hp=%.1f" % player.hp)

	# ---- 有甲：×0.7 向下取整 + 零头累计 ----
	inv.call("move_item", ["bag", free_slot], ["eq", "armor"])
	await _frames(2)
	player.hp = 100.0
	boss.set("_phase", 2)
	boss.set("_phase_t", 0.0)
	boss.set("_stars_fired", 24)   # 本段只测光环伤害，不让星点参进来
	boss.set("_dmg_t", 0.0)
	for i in 20:
		boss.call("_update_windup", 0.1)
	chk(abs(player.hp - 96.0) < 1e-6, "有甲：同样 2 秒只掉 4 血（0.21/跳累计取整），hp=%.1f" % player.hp)

	# ---- 整轮攻击时长（14.18 秒）的伤害量级 ----
	player.hp = 100.0
	boss.set("_phase", 2)
	boss.set("_phase_t", 0.0)
	boss.set("_stars_fired", 24)   # 本段只测光环伤害，不让星点参进来
	boss.set("_dmg_t", 0.0)
	var ticks := 0
	while int(boss.get("_phase")) == 2 and ticks < 400:
		boss.call("_update_windup", 0.1)
		ticks += 1
	chk(ticks >= 140, "攻击期持续约 %.1f 秒（%d 跳）" % [ticks * 0.1, ticks])
	chk(player.hp < 97.0, "一整轮攻击后确实掉血（hp=%.1f）" % player.hp)
	print("     一轮攻击掉血 %.1f 点（有甲，%d 跳）" % [100.0 - player.hp, ticks])

	# ---- 日月交替被驱动，而且是两轮（2026-09-04 起 2 倍速，攻击时长不变）----
	# 观察点：arena.set_day_night 把月光从 0 推到 0.55，所以"入夜"= moon.light_energy > 0.3
	boss.set("_phase", 2)
	boss.set("_phase_t", 0.0)
	boss.set("_stars_fired", 24)   # 本段只看天色，别让星点参进来
	boss.set("_dmg_t", 0.0)
	var arena: Node = boss.call("arena_node")
	arena.call("set_day_night", 0.0)
	var moon: Node = arena.get("_moon")
	chk(moon != null, "纯白空间里有月亮节点可以观察天色")
	var peaks := 0
	var lit := false
	var sky_ticks := 0
	var darkest := 0.0
	while int(boss.get("_phase")) == 2 and sky_ticks < 400:
		boss.call("_update_windup", 0.1)
		sky_ticks += 1
		var e := float(moon.light_energy)
		darkest = maxf(darkest, e)
		var on := e > 0.3
		if on and not lit:
			peaks += 1
		lit = on
	chk(peaks == 2, "一轮攻击里日升月落两轮（入夜 %d 次，%d 跳）" % [peaks, sky_ticks])
	chk(darkest > 0.5, "每轮都真的黑到底（最暗月光 %.2f / 上限 0.55）" % darkest)
	chk(absf(float(arena.get("_moon").light_energy) - 0.0) < 0.2,
		"攻击收尾回到白昼（月光 %.2f）" % float(arena.get("_moon").light_energy))

	# ---- 正面朝向玩家：把玩家挪到侧面，BOSS 视觉应转过去 ----
	player._exit_arena()
	await _frames(2)
	var vis: Node = boss.get("_visual")
	player.global_position = Vector3(boss.global_position.x + 20.0, boss.global_position.y, boss.global_position.z)
	for i in 40:
		boss.call("_process", 0.1)
	chk(abs(float(vis.rotation.y) - atan2(20.0, 0.0)) < 0.2,
		"BOSS 正面持续转向玩家（目标 %.2f，实际 %.2f）" % [atan2(20.0, 0.0), float(vis.rotation.y)])

	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
