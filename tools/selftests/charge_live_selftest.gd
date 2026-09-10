extends SceneTree
## 大运「锁定冲撞」活体自检：**不关任何节点的进程、不手动驱动**，让真实碰撞跑完一整轮。
##
## 为什么要有这一份：unit 版（charge_selftest）为了确定性把玩家的 _physics_process 关了，
## 于是玩家不会跟车头那块 StaticBody3D 较劲，车体中心线能径直扫过玩家 → 命中判定永远成立。
## 真人在游戏里是被车头挡着的那 5.6 米，中心线判定（±2.2 米）根本到不了他身上 ——
## 结果就是"车从你身上碾过去 28 米，不掉血、不击退、什么也没发生"。这类 bug 只有
## 让物理真的跑起来才看得见，所以这里专门做一次活体复现与回归。
##
## 断言：撞到了必须掉血；玩家不能被"犁"着跑一大段（撞了就停车）；停那一刻挂上 7.2 米
## 击退与 3 秒减速；最后人被顶在车前方而不是卡在车头里。

var fails: Array[String] = []
const MAX_FRAMES := 4000


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _arenas() -> Dictionary:
	var out := {}
	for a in get_nodes_in_group("arena"):
		out[String(a.call("theme_key"))] = a
	return out


func _run() -> void:
	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 88109)
	root.add_child(w)
	for _i in 30:
		await physics_frame
	var player := w.get_node("Player")
	var arenas := _arenas()
	var hw: Node = arenas.get("highway")
	chk(hw != null, "场景里有国道空间")
	var truck: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "truck":
			truck = b
	chk(truck != null, "找到大运")
	if truck == null or hw == null:
		_done()
		return

	# ---- 进战 ----
	player.global_position = Vector3(truck.global_position.x, truck.global_position.y + 1.0,
		truck.global_position.z + 8.0)
	for _i in 2:
		await physics_frame
	player.call("_enter_arena")
	for _i in 10:
		await physics_frame
	chk(bool(player.call("in_arena")) and bool(hw.call("is_active")), "已进国道空间开战")
	var floor_y: float = float(hw.call("floor_y"))

	# ---- 摆位：玩家站在车头正前方 12 米的行车道上，什么都不按（就是被碾的那个姿势）----
	var px: float = truck.global_position.x
	var pz: float = truck.global_position.z
	player.global_position = Vector3(px, floor_y + 1.05, pz + 12.0)
	player.set("hp", 100.0)
	for _i in 3:
		await physics_frame

	var armor: float = float(player.get("armor_factor"))
	var hp_min := float(player.get("hp"))
	var kb_max := 0.0
	var slow_max := 0.0
	var pin_move := 0.0              # 命中结算之前，玩家被车"顶着"走了多远
	var was_charging := false
	var ever_charged := false
	var ever_locked := false
	var frames := 0
	var prev_pp: Vector3 = player.global_position
	for i in MAX_FRAMES:
		await physics_frame
		frames = i
		hp_min = minf(hp_min, float(player.get("hp")))
		kb_max = maxf(kb_max, float(player.call("knockback_left")))
		slow_max = maxf(slow_max, float(player.get("_slow_t")))
		var charging_now := bool(truck.call("charging"))
		ever_locked = ever_locked or bool(truck.call("locked"))
		if charging_now:
			ever_charged = true
			if float(player.call("knockback_left")) <= 0.001:
				# 还没进入"停车结算"：这一段玩家位移全靠车身顶着，正是被犁的距离
				pin_move += prev_pp.distance_to(player.global_position)
		if was_charging and not charging_now:
			break
		prev_pp = player.global_position
		was_charging = charging_now

	chk(ever_locked, "它锁定位铺了预警带")
	chk(ever_charged, "它真的开撞了（不是卡在别的状态里）")
	chk(hp_min <= 100.0 - 20.0 * armor + 0.5,
		"正面被碾到 → 掉了这一撞的血（最低 %.1f，减伤系数 %.2f）" % [hp_min, armor])
	chk(kb_max > 7.0, "撞击完成后结算了 7.2 米击退（峰值 %.2f 米）" % kb_max)
	chk(slow_max > 2.9, "同时挂上 3 秒减速（峰值 %.2f 秒）" % slow_max)
	chk(pin_move < 5.0,
		"没有被车头顶着犁着跑：结算前的位移只有 %.1f 米（撞停生效）" % pin_move)
	# 让击退真跑完（0.2 秒 = 12 帧，多给几帧看余量），再量人离车多远
	for _i in 20:
		await physics_frame
	var gap: float = Vector2(player.global_position.x - truck.global_position.x,
		player.global_position.z - truck.global_position.z).length()
	chk(gap > 11.0, "收尾时人被顶到车外 %.1f 米，不是卡在车头里" % gap)
	chk(frames < MAX_FRAMES - 1, "整轮在 %d 帧内跑完（没卡死）" % frames)

	# ---- 再验一次"躲开就没有任何结算"：站到红带外面让它撞个空 ----
	player.call("_exit_arena")
	for _i in 6:
		await physics_frame
	player.global_position = Vector3(truck.global_position.x, truck.global_position.y + 1.0,
		truck.global_position.z + 8.0)
	player.call("_enter_arena")
	for _i in 10:
		await physics_frame
	px = truck.global_position.x
	pz = truck.global_position.z
	player.global_position = Vector3(px, floor_y + 1.05, pz + 12.0)     # 先正正当当站在车头前
	player.set("hp", 100.0)
	player.set("_slow_t", 0.0)
	player.set("_kb_left", 0.0)
	# 等它锁定（方向钉死）之后再横向迈出红带 —— 顺序很关键：先躲再锁等于让它瞄着你锁
	var locked_frames := 0
	while locked_frames < MAX_FRAMES and not bool(truck.call("locked")):
		await physics_frame
		locked_frames += 1
	chk(locked_frames < MAX_FRAMES, "第二轮：它也锁定了这一撞")
	player.global_position = Vector3(px + 6.5, floor_y + 1.05, pz + 12.0)
	hp_min = 100.0
	kb_max = 0.0
	slow_max = 0.0
	was_charging = false
	ever_charged = false
	prev_pp = player.global_position
	for i in MAX_FRAMES:
		await physics_frame
		hp_min = minf(hp_min, float(player.get("hp")))
		kb_max = maxf(kb_max, float(player.call("knockback_left")))
		slow_max = maxf(slow_max, float(player.get("_slow_t")))
		var charging_now2 := bool(truck.call("charging"))
		if charging_now2:
			ever_charged = true
		if was_charging and not charging_now2:
			break
		prev_pp = player.global_position
		was_charging = charging_now2
	chk(ever_charged, "第二轮也开撞了（这次是撞空）")
	chk(kb_max < 0.001 and slow_max < 0.001,
		"躲出红带 → 没有任何击退与减速（击退峰值 %.2f，减速峰值 %.2f）" % [kb_max, slow_max])
	print("     （躲开的第二轮：血量最低 %.1f，含尾气蹭伤）" % hp_min)
	_done()


func _done() -> void:
	print("\n== 活体冲撞自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
