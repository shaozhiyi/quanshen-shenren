extends SceneTree
## 砸落技能（升空 1.5×、空中追踪 2s → 红圈 1s → 砸落命中 -20 + 地裂）与玩家二段跳的无头自检

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== 砸落 / 二段跳自检 ==")
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _fx_count() -> int:
	return get_nodes_in_group("slam_fx").size()


func _marker_visible(boss: Node) -> bool:
	var mk: MeshInstance3D = boss.get("_marker")
	return mk != null and mk.visible


func _park(boss: Node, player: Node, px: float, base_y: float) -> void:
	## 停掉游走并把 BOSS 复位到原点，玩家放在 x=px 处（判定半径 6 米内/外）
	boss.set("_wandering", false)
	boss.global_position = Vector3(0.0, base_y, 0.0)
	player.global_position = Vector3(px, base_y + 1.0, 0.0)


func _star_at(w: Node, center: Vector3, damage: float, straight_down := false) -> void:
	## 生成一颗星点弹：默认从玩家上方 14 米、后方 8 米俯冲穿过胸口；straight_down 则原地竖直落下（打偏用）
	## 起点抬高是因为星点现在"碰到地板才消失"，平射会被地形起伏提前拦下
	var FX: GDScript = load("res://scripts/slam_fx.gd")
	var from: Vector3 = center + Vector3(0.0, 14.0, -8.0)
	var dir: Vector3 = Vector3.DOWN if straight_down else (center + Vector3(0.0, 0.9, 0.0) - from).normalized()
	FX.spawn_star(w, from, dir, 42.0, 6.0, 1.5, damage)


func _drive(boss: Node, seconds: float, keep_phase: int = -1) -> int:
	## 按固定步长喂相位机；keep_phase>=0 时一旦离开该相位就停（防止顺手推进下一个相位）
	var steps := int(seconds / 0.1)
	var i := 0
	for k in steps:
		if keep_phase >= 0 and int(boss.get("_phase")) != keep_phase:
			break
		boss.call("_update_windup", 0.1)
		i += 1
	return i


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	w.get_node("Ground").set("seed_value", 141421)
	root.add_child(w)
	await _frames(8)
	var player := w.get_node("Player")
	var inv := w.get_node("HUD/Inventory")
	var boss: Node = player.call("bosses")[0]
	var arena: Node = boss.call("arena_node")
	var base_y := float(arena.call("floor_y"))

	# ---- 1. 进空间，升空高度 ×1.5 ----
	player.global_position = Vector3(boss.global_position.x, boss.global_position.y + 1.0, boss.global_position.z + 8.0)
	player._enter_arena()
	chk(abs(float(boss.position.y) - base_y) < 0.01, "开战时 BOSS 站在地面 %.1f" % base_y)
	boss.set("_phase", 1)
	boss.set("_phase_t", 0.0)
	_drive(boss, 11.4, 1)
	chk(int(boss.get("_phase")) == 2, "前摇 11.1 秒后进入攻击相位（实际 %d）" % int(boss.get("_phase")))
	_drive(boss, 1.6, 2)
	var peak := float(boss.position.y) - base_y
	chk(peak > 19.7 and peak < 21.2, "升空高度 %.2f 米 ≈ 13.5×1.5（20.25）" % peak)

	# ---- 2. 攻击期逐颗射出星点；技能放完 → 空中追踪 2 秒，跟着玩家走 ----
	boss.set("_phase", 2)
	boss.set("_phase_t", 0.0)
	boss.call("_hide_stars")          # 计数归零
	boss.call("_layout_stars", 1.0)   # 先摆好环绕位置
	for st in boss.get("_stars"):
		(st as MeshInstance3D).visible = true     # 视作已蓄满 24 颗
	_drive(boss, 7.0, 2)
	var fired_mid := int(boss.get("_stars_fired"))
	chk(fired_mid > 8 and fired_mid < 16, "攻击进行到一半已射出 %d / 24 颗（渐进）" % fired_mid)
	_drive(boss, 8.0, 2)
	chk(int(boss.get("_phase")) == 4, "攻击 14.18 秒后不直接落地，转入空中追踪（相位 %d）" % int(boss.get("_phase")))
	chk(int(boss.get("_stars_fired")) == 24, "日月交替结束刚好射完全部 24 颗（实际 %d）" % int(boss.get("_stars_fired")))
	var lit := 0
	for st in boss.get("_stars"):
		if (st as MeshInstance3D).visible:
			lit += 1
	chk(lit == 0, "星点池已全部熄灭（可见 %d 颗）" % lit)
	chk(get_nodes_in_group("slam_star").size() >= 20, "射出的星点已生成弹体（当前 %d 个在飞）" % get_nodes_in_group("slam_star").size())
	chk(float(boss.position.y) - base_y > 19.0, "追踪期间仍在高空（%.1f 米）" % (float(boss.position.y) - base_y))
	player.global_position = Vector3(boss.global_position.x + 40.0, base_y + 1.0, boss.global_position.z)
	_drive(boss, 2.2, 4)
	var gap := absf(float(boss.position.x) - player.global_position.x)
	chk(int(boss.get("_phase")) == 5, "追踪满 2 秒 → 锁定并进入红圈预警（相位 %d）" % int(boss.get("_phase")))
	chk(gap < 10.0, "2 秒追踪把 40 米差距缩到 %.1f 米（带滞后，能靠跑动甩开）" % gap)
	chk(_marker_visible(boss), "锁定时红圈已显示")
	var locked := Vector2(boss.global_position.x, boss.global_position.z)

	# ---- 3. 红圈 1 秒后砸落：越落越快，落点=锁定位置 ----
	_drive(boss, 1.2, 5)
	chk(int(boss.get("_phase")) == 6, "预警满 1 秒 → 开始砸落（相位 %d）" % int(boss.get("_phase")))
	var y0 := float(boss.position.y)
	_drive(boss, 0.2, 6)
	var y1 := float(boss.position.y)
	chk(y1 < y0 - 1.5, "砸落中高度快速下降 %.1f → %.1f" % [y0 - base_y, y1 - base_y])
	# 玩家站在圈外 30 米：应该砸空
	player.global_position = Vector3(boss.global_position.x + 30.0, base_y + 1.0, boss.global_position.z)
	player.hp = 100.0
	var fx_before := _fx_count()
	_drive(boss, 0.5, 6)
	chk(int(boss.get("_phase")) == 0, "砸完回到待机相位（相位 %d）" % int(boss.get("_phase")))
	chk(abs(float(boss.position.y) - base_y) < 0.01, "落地后回到地面")
	chk(bool(boss.get("_wandering")), "砸地完成后开始正常移动")
	chk(not bool(boss.call("slam_hit")), "圈外 30 米 → 判定砸空")
	chk(abs(float(player.hp) - 100.0) < 1e-6, "砸空不掉血（hp=%.1f）" % float(player.hp))
	chk(_fx_count() == fx_before + 1, "砸地生成 1 个地裂特效节点（%d → %d）" % [fx_before, _fx_count()])
	chk(not _marker_visible(boss), "砸完收起红圈")
	chk(Vector2(boss.global_position.x, boss.global_position.z).distance_to(locked) < 0.01,
		"落点就是锁定点（偏移 %.2f 米）" % Vector2(boss.global_position.x, boss.global_position.z).distance_to(locked))

	# ---- 4. 命中与伤害（直接调结算，隔离光环干扰） ----
	# 注意：砸完 BOSS 立刻以 45 米/秒游走，每次判定前都要重新摆位，否则会被"跑"出圈外
	player.hp = 100.0
	_park(boss, player, 3.0, base_y)      # 圈内（半径 6）
	boss.call("_do_slam_impact", player)
	chk(bool(boss.call("slam_hit")), "圈内 3 米 → 命中")
	chk(abs(float(player.hp) - 86.0) < 1e-6, "有甲：20×0.7=14 → hp=%.1f" % float(player.hp))
	# 脱甲：整 20 点
	var free_slot := -1
	for i in 27:
		if String(inv.call("bag_get", i)) == "":
			free_slot = i
			break
	inv.call("move_item", ["eq", "armor"], ["bag", free_slot])
	await _frames(2)
	player.hp = 100.0
	_park(boss, player, 3.0, base_y)
	boss.call("_do_slam_impact", player)
	chk(abs(float(player.hp) - 80.0) < 1e-6, "无甲：整整 -20（hp=%.1f）" % float(player.hp))
	inv.call("move_item", ["bag", free_slot], ["eq", "armor"])
	await _frames(2)
	# 圈外 7 米
	player.hp = 100.0
	_park(boss, player, 7.0, base_y)
	boss.call("_do_slam_impact", player)
	chk(not bool(boss.call("slam_hit")), "圈外 7 米（半径 6）→ 不命中")
	chk(abs(float(player.hp) - 100.0) < 1e-6, "圈外不掉血")
	# 无敌期被砸：完全免疫
	player.call("gain_invincibility", 10.0)
	player.hp = 100.0
	_park(boss, player, 0.0, base_y)
	boss.call("_do_slam_impact", player)
	chk(abs(float(player.hp) - 100.0) < 1e-6, "无敌期被砸不掉血")
	player.call("_end_invincibility")
	# 强化过的防具进一步减免
	player.enhance_levels["armor"] = 10
	player.call("_refresh_armor_factor")
	player.hp = 100.0
	_park(boss, player, 2.0, base_y)
	boss.call("_do_slam_impact", player)
	chk(abs(float(player.hp) - 92.0) < 1e-6, "防具 +10（×0.40）：20 → 8 血（hp=%.1f）" % float(player.hp))
	player.enhance_levels["armor"] = 0
	player.call("_refresh_armor_factor")

	# ---- 5. 离场再进：红圈与相位干净复位 ----
	player._exit_arena()
	await _frames(3)
	chk(not _marker_visible(boss) and int(boss.get("_phase")) == 0, "离场后相位与红圈复位")
	player.global_position = Vector3(boss.global_position.x, boss.global_position.y + 1.0, boss.global_position.z + 8.0)
	player._enter_arena()
	chk(int(boss.get("_phase")) == 0, "再开战从待机相位重新开始")
	player._exit_arena()

	# ---- 6. 二段跳 ----
	await _frames(60)
	chk(bool(player.is_on_floor()), "回到大地图并已落地")
	chk(int(player.call("air_jumps_left")) == 1, "落地补满空中跳数")
	var r1 := int(player.call("try_jump"))
	chk(r1 == 1, "地面起跳 → 返回 1（实际 %d）" % r1)
	chk(float(player.velocity.y) > 4.0, "起跳给向上速度 %.2f" % float(player.velocity.y))
	await _frames(3)
	chk(not bool(player.is_on_floor()), "已离地")
	var r2 := int(player.call("try_jump"))
	chk(r2 == 2, "空中再跳 → 二段跳（返回 %d）" % r2)
	chk(abs(float(player.velocity.y) - 4.5 * 0.92) < 1e-6, "二段跳力度 %.2f（略弱于一段）" % float(player.velocity.y))
	var r3 := int(player.call("try_jump"))
	chk(r3 == 0, "三跳被拒（返回 %d）" % r3)
	chk(int(player.call("air_jumps_left")) == 0, "空中跳数已耗尽")
	chk(_fx_count() >= 1, "二段跳留下一圈光环特效（当前 %d 个）" % _fx_count())
	await _frames(220)
	chk(_fx_count() == 0, "地裂/星点/光环特效全部播完自毁（剩 %d 个）" % _fx_count())

	# ---- 7. 弓箭数值与"提示已下线"回归 ----
	var bow: Node = w.get_node("Player/Camera3D/Bow")
	chk(abs(float(bow.call("charge_time")) - 2.0) < 1e-6, "满蓄时间已改为 2 秒")
	var dr: Array = bow.call("damage_range")
	chk(int(dr[0]) == 12 and int(dr[1]) == 70, "弓箭伤害 12~70（实际 %s）" % str(dr))
	var scale3 := float(player.call("damage_scale_for", "sword"))
	chk(abs(scale3 - 1.0) < 1e-6, "未强化时倍率 1.0")
	player.enhance_levels["bow"] = 3
	chk(abs(float(bow.call("_player_damage_scale")) - pow(1.1, 3.0)) < 1e-6,
		"弓 +3 → 满蓄 70×1.1³=%.1f" % floor(70.0 * pow(1.1, 3.0)))
	player.enhance_levels["bow"] = 0
	# 提示通道整体移除：这些方法/信号都不该再存在
	chk(not player.has_method("_toast"), "玩家侧 _toast 已删除")
	chk(not w.get_node("HUD").has_method("toast"), "HUD toast 通道已删除")
	chk(not inv.has_method("flash_hint"), "背包面板 flash_hint 已删除")
	chk(not boss.has_method("phase_text"), "BOSS 分相位文案已删除")
	chk(not boss.has_signal("slam_landed"), "slam_landed 信号已删除")
	chk(bool(player.is_on_floor()) and int(player.call("air_jumps_left")) == 1, "落地后又能二段跳")

	# ---- 8. 星点命中伤害 ----
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var pp: Vector3 = player.global_position
	# 有甲：5×0.7=3.5 → 取整先扣 3，零头累计到下一发（第二发扣 4）
	player.hp = 100.0
	_star_at(w, pp, 5.0)
	await _frames(40)
	chk(abs(float(player.hp) - 97.0) < 1e-6, "有甲第一发：3.5 取整扣 3（hp=%.1f）" % float(player.hp))
	_star_at(w, pp, 5.0)
	await _frames(40)
	chk(abs(float(player.hp) - 93.0) < 1e-6, "有甲第二发：零头累计后扣 4（hp=%.1f）" % float(player.hp))
	# 打偏：从 20 米外竖直落下
	player.hp = 100.0
	_star_at(w, pp + Vector3(20.0, 0.0, 0.0), 5.0, true)
	await _frames(40)
	chk(abs(float(player.hp) - 100.0) < 1e-6, "打偏不造成伤害（hp=%.1f）" % float(player.hp))
	# 无敌期：完全免疫
	player.call("gain_invincibility", 10.0)
	_star_at(w, pp, 5.0)
	await _frames(40)
	chk(abs(float(player.hp) - 100.0) < 1e-6, "无敌期星点不掉血（hp=%.1f）" % float(player.hp))
	player.call("_end_invincibility")
	# 脱甲：整 5 点
	var slot2 := -1
	for i in 27:
		if String(inv.call("bag_get", i)) == "":
			slot2 = i
			break
	inv.call("move_item", ["eq", "armor"], ["bag", slot2])
	await _frames(2)
	player.hp = 100.0
	_star_at(w, pp, 5.0)
	await _frames(40)
	chk(abs(float(player.hp) - 95.0) < 1e-6, "无甲单发命中 -5（hp=%.1f）" % float(player.hp))
	# 端到端：整轮星点射完后总掉血应是 5 的倍数（红 10 / 黄 5 / 蓝 5 / 绿 0，全程不穿防具）
	player.set("_dmg_carry", 0.0)
	await _frames(2)
	player.global_position = Vector3(boss.global_position.x, boss.global_position.y + 1.0, boss.global_position.z + 8.0)
	player._enter_arena()
	await _frames(2)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	pp = player.global_position
	boss.set("_phase", 2)
	boss.set("_phase_t", 0.0)
	boss.call("_hide_stars")
	boss.call("_layout_stars", 1.0)
	for st in boss.get("_stars"):
		(st as MeshInstance3D).visible = true
	_drive(boss, 14.0, 2)
	chk(int(boss.get("_stars_fired")) >= 20, "整轮已射出 %d 颗星点" % int(boss.get("_stars_fired")))
	boss.set("_phase", 0)          # 停掉光环持续掉血，只留星点在飞
	boss.set("_phase_t", 99.0)     # 让它停在待机不重新蓄力
	boss.set("_wandering", false)
	player.hp = 100.0
	await _frames(60)
	var lost := 100.0 - float(player.hp)
	chk(lost >= 5.0 and fmod(lost, 5.0) < 1e-4, "星点弹幕总掉血 %.0f（5 的倍数，命中 %d 发）" % [lost, int(lost / 5.0)])
	player._exit_arena()

	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
