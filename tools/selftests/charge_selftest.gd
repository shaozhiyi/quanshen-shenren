extends SceneTree
## 大运「锁定冲撞」无头自检：
##  1) 名册接线（charge_lock/units/speed_mult/gap/damage/knockback/ring_damage + no_turn），狗奶没这招
##  2) 数值换算：行程 = 8 个冲刺距离 ≈ 28.8 米，速度 = 玩家奔跑 3 倍 = 30 米/秒
##  3) 锁定后不转向：预警期间方向钉死，玩家横移它也不跟着改线；车轮停转、车身整帧冻住
##  4) 躲开红带的一撞：逐帧推进、每帧位移 ≤ 一帧的路、整段 ≈28.8 米且严格走直线，
##     并且什么结算都不给（不掉血、不记命中、不欠击退与减速）
##  5) 收尾光波：扩到半径内才扣 10 血，站得远扫不到，且一轮只扫一次
##  6) 击退自己跑一遍物理：0.2 秒内被推开 ≈7.2 米后交还操作权
##  7) 正面碾到人（本次回归）：命中必须成立 → 掉 20 血、当场停车（不会把人钉在车头上
##     犁着跑）、停车即结算 7.2 米击退 + 3 秒 ×0.5 减速，随后光波再扫到扣 10
##     压到人之前的每一帧身上都不该有击退与减速
##  8) 红色提示是沿撞击路径铺的长条预警带（不是光环）：位置/朝向/尺寸都对，且车冲出去它留在原地
##  9) 回归：车被 confine 夹在国道里；锁定冻结这一秒尾气照旧掉血；狗奶那套没被牵连

var fails: Array[String] = []
const DT := 1.0 / 60.0
const FX := preload("res://scripts/slam_fx.gd")


## spawn_slam 不返回实例，只能按"第 from 个之后新增的 slam_fx 子节点"把它捞出来
func _new_fx(parent: Node, from: int) -> Node:
	var kids := parent.get_children()
	for i in range(from, kids.size()):
		var k: Node = kids[i]
		if k.get_script() == FX:
			return k
	return null


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _arenas() -> Dictionary:
	var out := {}
	for a in get_nodes_in_group("arena"):
		out[String(a.call("theme_key"))] = a
	return out


## 手动推进 BOSS 一整帧（_process 里含车头朝向 + 载具 AI），便于确定性断言
func _pump(t: Node, n: int) -> void:
	for _i in n:
		t.call("_process", DT)


func _pump_until(t: Node, max_frames: int, cond: Callable) -> int:
	for i in max_frames:
		t.call("_process", DT)
		if bool(cond.call()):
			return i + 1
	return -1


func _run() -> void:
	var ROSTER: GDScript = load("res://scripts/boss_roster.gd")

	# ---- 1. 名册接线 ----
	var dtruck: Dictionary = ROSTER.def("truck")
	var dmilk: Dictionary = ROSTER.def("dogmilk")
	chk(absf(float(dtruck.get("charge_lock", 0.0)) - 2.0) < 0.001, "名册：锁定预警 2 秒")
	chk(absf(float(dtruck.get("charge_units", 0.0)) - 8.0) < 0.001, "名册：撞击行程 = 8 个冲刺距离")
	chk(absf(float(dtruck.get("charge_speed_mult", 0.0)) - 3.0) < 0.001, "名册：冲撞速度 = 玩家奔跑 ×3")
	chk(absf(float(dtruck.get("charge_damage", 0.0)) - 20.0) < 0.001, "名册：撞上 20 血")
	chk(absf(float(dtruck.get("charge_gap", 0.0)) - 7.0) < 0.001, "名册：撞完冷却 7 秒")
	chk(absf(float(dtruck.get("charge_knockback", 0.0)) - 2.0) < 0.001, "名册：撞上击退 2 个冲刺距离")
	chk(absf(float(dtruck.get("charge_slow_sec", 0.0)) - 3.0) < 0.001, "名册：撞上减速 3 秒")
	chk(absf(float(dtruck.get("charge_ring_damage", 0.0)) - 10.0) < 0.001, "名册：收尾光波 10 血")
	chk(bool(dtruck.get("no_turn", false)), "名册：大运是 no_turn 载具档（不转向对玩家）")
	chk(float(dtruck.get("blink_wait", 0.0)) == 0.0 and float(dmilk.get("charge_lock", 0.0)) == 0.0,
		"名册：瞬移那招已删除，狗奶也没配冲撞")

	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 88103)
	root.add_child(w)
	await _frames(25)
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
	chk(not bool(truck.get("_faces_player")), "载具档：车头不再永远正对玩家")

	# ---- 2. 数值换算 ----
	var cd: float = truck.call("charge_dist")
	chk(absf(cd - 28.8) < 0.01, "撞击行程 = 3.6 × 8 = 28.8 米（实测 %.2f）" % cd)
	var reach: float = truck.call("charge_reach")
	chk(absf(reach - (28.8 + 5.3)) < 0.01, "最远够到 = 行程 + 半个车长（%.1f 米）" % reach)

	# ---- 进战：站到它旁边再开，之后手动驱动 ----
	player.global_position = Vector3(truck.global_position.x, truck.global_position.y + 1.0,
		truck.global_position.z + 8.0)
	await _frames(2)
	player.call("_enter_arena")
	await _frames(8)
	chk(bool(player.call("in_arena")) and bool(hw.call("is_active")), "已进国道空间")
	var c: Vector3 = hw.call("center")
	var floor_y: float = float(hw.call("floor_y"))
	var speed: float = truck.call("charge_speed_ref")
	chk(absf(speed - 30.0) < 1.0, "冲撞速度 = 玩家奔跑(10) ×3 = 30 米/秒（实测 %.2f）" % speed)

	player.process_mode = Node.PROCESS_MODE_DISABLED
	truck.process_mode = Node.PROCESS_MODE_DISABLED      # 之后只由本测试逐帧手动驱动

	# ---- 3. 锁定 + 预警带 ----
	var pz := c.z + 8.0
	var px: float = c.x + 12.5
	player.global_position = Vector3(px, floor_y + 1.05, pz)
	truck.global_position = Vector3(px, floor_y, pz - 14.0)      # 正前方 14 米，够得着
	truck.call("_reset_charge")      # 进战路上它可能已经抢先锁定，这里清干净再测
	truck.set("_charge_cd", 0.0)
	_pump(truck, 1)
	chk(bool(truck.call("locked")), "第一帧就进入锁定（原地冻结）")
	var lane: MeshInstance3D = truck.get("_lane")
	chk(lane != null and lane.visible, "锁定时地面亮起红色预警带")
	_pump(truck, 3)
	var lane_mat: StandardMaterial3D = truck.get("_lane_mat")
	chk(lane_mat != null and lane_mat.albedo_color.a > 0.0, "预警带会淡入（不是光环那种一圈）")
	var pmesh: PlaneMesh = lane.mesh
	chk(absf(float(pmesh.size.y) - cd) < 0.01, "预警带长度 = 撞击行程（%.1f 米）" % float(pmesh.size.y))
	chk(float(pmesh.size.x) > 2.5 and float(pmesh.size.x) < 5.0, "预警带宽度 ≈ 车宽（%.1f 米）" % float(pmesh.size.x))
	var lane_from_truck: float = lane.global_position.distance_to(truck.global_position)
	chk(absf(lane_from_truck - (5.3 + cd * 0.5)) < 0.5,
		"预警带中心铺在车头前方（离车身中心 %.1f 米）" % lane_from_truck)
	chk(lane.global_position.y > floor_y and lane.global_position.y < floor_y + 0.5, "预警带贴在地面上方")
	var heading0: float = float(truck.get("_heading"))
	var dir0: Vector3 = truck.get("_charge_dir")
	var frozen_at: Vector3 = truck.global_position
	chk(dir0.z > 0.99 and absf(dir0.x) < 0.02, "锁定方向朝玩家（+Z）")

	# 预警期把玩家横向挪开：方向不能跟着改
	_pump(truck, 30)
	player.global_position = Vector3(px + 6.0, floor_y + 1.05, pz)
	_pump(truck, 30)
	var dir1: Vector3 = truck.get("_charge_dir")
	var heading1: float = float(truck.get("_heading"))
	chk(dir1.distance_to(dir0) < 0.001 and absf(heading1 - heading0) < 0.0001,
		"锁定后不转向：玩家横移 6 米，撞击方向一字不改")
	chk(truck.global_position.distance_to(frozen_at) < 0.05, "预警期间整辆车冻在原地")

	# ---- 4. 躲开红带的一撞：整段 28.8 米逐帧推进、且什么结算都不给 ----
	#    （玩家在 §3 预警期已经横向挪到 px+6.0，站出了那条带子）
	player.set("hp", 100.0)
	player.set("_dmg_carry", 0.0)
	player.set("_slow_t", 0.0)
	player.set("_kb_left", 0.0)
	player.set("_kb_speed", 0.0)
	truck.set("_dmg_t", 0.0)
	truck.set("_aura_dmg", 0.0)                                   # 只测撞击伤害
	var fx_cnt: int = truck.get_parent().get_child_count()        # 收尾光波会被加进这里
	var moved_max := 0.0
	var prev: Vector3 = truck.global_position
	var frames := _pump_until(truck, 400, Callable(truck, "charging"))
	chk(frames > 0, "预警 2 秒到点开撞")
	var mid: Vector3 = truck.global_position
	chk(mid.distance_to(frozen_at) < 1.0, "刚开撞时车还在原地附近（%.2f 米）" % mid.distance_to(frozen_at))
	var charge_frames := 0
	for i in 200:
		truck.call("_process", DT)
		charge_frames += 1
		var now: Vector3 = truck.global_position
		moved_max = maxf(moved_max, now.distance_to(prev))
		prev = now
		if not bool(truck.call("charging")):
			break
	var trav: Vector3 = truck.global_position - frozen_at
	chk(moved_max < speed * DT * 1.3,
		"逐帧推进：单帧最大位移 %.2f 米（限速 %.2f，不是瞬移）" % [moved_max, speed * DT])
	chk(absf(trav.length() - 28.8) < 0.8, "没人挡路 → 整段冲撞走了 ≈28.8 米（实测 %.2f）" % trav.length())
	chk(absf(trav.x) < 0.05 and trav.z > 28.0, "严格走直线：只有沿锁定方向的位移（x 偏 %.2f）" % trav.x)
	var sec: float = charge_frames * DT
	chk(sec > 0.7 and sec < 1.3, "冲撞耗时 ≈0.96 秒（28.8 米 ÷ 30 米/秒，实测 %.2f）" % sec)
	chk(absf(float(player.get("hp")) - 100.0) < 0.01,
		"横移出带子 → 一点没撞着（剩 %.1f）" % float(player.get("hp")))
	chk(not bool(truck.get("_charge_hit")) and not bool(truck.get("_charge_kb_pending")),
		"没撞上：既不记命中，也不欠击退")
	chk(absf(float(player.get("_slow_t"))) < 0.001 and absf(float(player.call("knockback_left"))) < 0.001,
		"没撞上 → 冲完也没有击退与减速（不会空欠一发）")
	chk(absf(float(truck.get("_charge_cd")) - 7.0) < 0.001 and absf(float(truck.call("charge_gap_time")) - 7.0) < 0.001,
		"撞完进入 7 秒冷却，不会连着再撞")
	chk(lane != null and not lane.visible, "冲撞结束后预警带收起")

	# ---- 5. 收尾光波：扩到人才掉血、够不着就不掉、一轮只扫一次 ----
	var rc := Vector3.ZERO            # 光波中心，§6 还要用（GDScript 的 if 块有作用域，先提到外面）
	var ring: Node = _new_fx(truck.get_parent(), fx_cnt)
	chk(ring != null, "撞到底留下了收尾光波（slam_fx 实例）")
	if ring != null:
		var rr: float = float(ring.get("_radius"))
		chk(absf(rr - float(truck.call("charge_ring_radius"))) < 0.01,
			"光波半径 = 行程的三成五（%.1f 米）" % rr)
		chk(absf(float(ring.get("_ring_damage")) - 10.0) < 0.001, "光波伤害 10")
		var reach_max := rr * float(FX.RING_RIM)
		rc = ring.global_position
		var d_now := Vector2(player.global_position.x - rc.x, player.global_position.z - rc.z).length()
		player.set("hp", 100.0)
		player.set("_dmg_carry", 0.0)
		chk(d_now > reach_max, "玩家此刻离光波中心 %.1f 米 > 判定上限 %.1f 米" % [d_now, reach_max])
		for _i in 90:
			ring.call("_process", DT)                              # 1.5 秒：圈早扩到头了
		chk(absf(float(player.get("hp")) - 100.0) < 0.01,
			"站在圈外 → 整圈扩完也扫不到（剩 %.1f）" % float(player.get("hp")))
		player.global_position = Vector3(rc.x, floor_y + 1.05, rc.z - 8.0)     # 走进 8 米 = 圈内
		for _i in 6:
			ring.call("_process", DT)
		var hp_ring: float = float(player.get("hp"))
		var exp_ring: float = 100.0 - 10.0 * float(player.get("armor_factor"))
		chk(absf(hp_ring - exp_ring) < 0.01,
			"被扩开的圈扫到 = 10 血（防具 ×%.2f 后剩 %.1f）" % [float(player.get("armor_factor")), hp_ring])
		for _i in 30:
			ring.call("_process", DT)
		chk(absf(float(player.get("hp")) - hp_ring) < 0.01, "同一圈不重复结算（仍是 %.1f）" % float(player.get("hp")))

	# ---- 6. 击退真的把人推开 ≈7.2 米，推完交还操作权 ----
	# move_and_slide 只在真物理帧里生效，这一小节要把玩家的进程放回来（其余小节仍是手动驱动）
	player.global_position = Vector3(rc.x, floor_y + 1.05, rc.z - 22.0)
	player.set("hp", 100.0)
	player.set("_kb_left", 0.0)
	player.set("_kb_speed", 0.0)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await physics_frame
	var kb_ok: bool = bool(player.call("knockback", dir1, float(truck.call("charge_kb_dist"))))
	chk(kb_ok, "knockback() 接受方向与距离")
	var kb_from: Vector3 = player.global_position
	await _frames(12)          # 每帧 36÷60 = 0.6 米，12 帧正好推完 7.2 米（再多等的就是正常的速度衰减）
	var kb_moved := Vector2(player.global_position.x - kb_from.x,
		player.global_position.z - kb_from.z).length()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	chk(kb_moved > 6.2 and kb_moved < 8.2,
		"0.2 秒内被推开 ≈7.2 米（实测 %.2f）" % kb_moved)
	chk(float(player.call("knockback_left")) < 0.001, "推完清零，之后玩家自己的按键说了算")
	player.set("_kb_dir", Vector3.ZERO)

	# ---- 7. 正面碾到人：掉血 + 撞停 + 击退/减速结算 + 光波连招 ----
	#      （回归：判定只按中心线时，车头那块实体碰撞会把人挡在 5.6 米外，永远判不中）
	player.set("hp", 100.0)
	player.set("_dmg_carry", 0.0)
	player.set("_slow_t", 0.0)
	player.set("_kb_left", 0.0)
	player.set("_kb_speed", 0.0)
	truck.global_position = Vector3(px, floor_y, pz - 14.0)
	player.global_position = Vector3(px, floor_y + 1.05, pz)     # 站回带子里，车头正前 14 米
	truck.call("_reset_charge")
	truck.set("_charge_cd", 0.0)
	truck.set("_dmg_t", 0.0)
	truck.set("_aura_dmg", 0.0)
	_pump(truck, 2)
	chk(bool(truck.call("locked")), "撞上这一轮：先原地锁定")
	var f2: int = _pump_until(truck, 400, Callable(truck, "charging"))
	chk(f2 > 0, "预警到点开撞（正面有人也不改变方向）")
	var fx_cnt_hit: int = truck.get_parent().get_child_count()
	var hit_start: Vector3 = truck.global_position
	var clean_before := true
	for i in 300:
		truck.call("_process", DT)
		if not bool(truck.get("_charge_hit")):
			var no_kb := float(player.call("knockback_left")) < 0.001
			var no_slow := float(player.get("_slow_t")) < 0.001
			clean_before = clean_before and no_kb and no_slow
		if not bool(truck.call("charging")):
			break
	var hit_travel: float = truck.global_position.distance_to(hit_start)
	chk(clean_before, "压到人之前身上不会有击退与减速（结算只发生在撞击完成时）")
	chk(bool(truck.get("_charge_hit")), "正面碾到玩家 → 命中判定成立（回归：以前永远判不中）")
	var exp_hit: float = 100.0 - 20.0 * float(player.get("armor_factor"))
	chk(absf(float(player.get("hp")) - exp_hit) < 0.01,
		"撞上扣 20 血（防具 ×%.2f 后剩 %.1f）" % [float(player.get("armor_factor")), float(player.get("hp"))])
	chk(hit_travel > 3.0 and hit_travel < 12.5,
		"撞到人就当场停车，不会把人钉在车头上犁着跑（本轮走了 %.1f 米，行程上限 28.8）" % hit_travel)
	var kb7: float = float(player.call("knockback_left"))
	chk(absf(kb7 - 7.2) < 0.01, "停车即结算：挂上 7.2 米击退（实测 %.2f）" % kb7)
	chk(absf(float(player.get("_slow_t")) - 3.0) < 0.001, "停车即结算：挂上 3 秒减速")
	chk(absf(float(player.call("speed_now")) - 2.5) < 0.01,
		"减速期间移速 = 步行 5 × 0.5 = %.1f 米/秒" % float(player.call("speed_now")))
	var kb_dir7: Vector3 = player.get("_kb_dir")
	chk(absf(float(player.get("_kb_speed")) - 36.0) < 0.01 and kb_dir7.distance_to(dir1) < 0.01,
		"击退 0.2 秒内推完（%.1f 米/秒），方向 = 钉死的撞击方向" % float(player.get("_kb_speed")))
	chk(not bool(truck.get("_charge_kb_pending")), "结算完不欠账，下一轮不会补发")
	var ring2: Node = _new_fx(truck.get_parent(), fx_cnt_hit)
	chk(ring2 != null, "撞停的位置也甩出收尾光波")
	if ring2 != null:
		for _i in 8:
			ring2.call("_process", DT)
		var exp2: float = exp_hit - 10.0 * float(player.get("armor_factor"))
		chk(absf(float(player.get("hp")) - exp2) < 0.01,
			"停在人身边 → 光波接着扫到（再扣 10，剩 %.1f）" % float(player.get("hp")))
	var lane_end: Vector3 = lane.global_position
	_pump(truck, 20)
	chk(lane.global_position.distance_to(lane_end) < 0.001 or not lane.visible,
		"预警带钉在地面上，不会跟着车往前滑")

	# ---- 8. 车被夹在国道上（_move_truck 每帧都过一遍 confine）----
	var hi_x: float = float(hw.call("confine", Vector3(c.x + 1e6, floor_y, c.z)).x) - c.x
	var lo_x: float = float(hw.call("confine", Vector3(c.x - 1e6, floor_y, c.z)).x) - c.x
	truck.global_position = Vector3(c.x + 900.0, floor_y, c.z - 500.0)
	truck.call("_move_truck", Vector3(0.0, 0.0, 1.0))
	chk(truck.global_position.x - c.x <= hi_x + 0.01,
		"车冲出路肩 → 被夹回外侧护栏内（x=%.1f ≤ %.1f）" % [truck.global_position.x - c.x, hi_x])
	chk(absf((truck.global_position.z - (c.z - 500.0)) - 1.0) < 0.01, "沿路方向照样推进（z +1 米）")
	truck.global_position = Vector3(c.x - 50.0, floor_y, c.z)
	truck.call("_move_truck", Vector3(0.0, 0.0, 1.0))
	chk(truck.global_position.x - c.x >= lo_x - 0.01,
		"压进中央隔离带也被夹回（x=%.1f ≥ %.1f）" % [truck.global_position.x - c.x, lo_x])
	chk(absf(truck.global_position.y - floor_y) < 0.01, "位移后仍贴回地板高度")

	# ---- 9. 回归：冻结期间尾气照旧掉血 ----
	player.global_position = Vector3(px, floor_y + 1.05, pz)
	truck.global_position = Vector3(px, floor_y, pz - 3.0)             # 玩家就在车尾边，在尾气里
	truck.set("_aura_dmg", 0.3)
	truck.set("_charge_cd", 0.0)
	truck.set("_dmg_t", 0.0)
	truck.set("hp", 2000.0)
	player.set("hp", 100.0)
	truck.call("_reset_charge")
	truck.set("_charge_t", 1.0)
	truck.set("_aim_locked", true)
	var froze: Vector3 = truck.global_position
	_pump(truck, 60)
	chk(float(player.get("hp")) < 100.0,
		"锁定的 1 秒里尾气照旧掉血（剩 %.1f）" % float(player.get("hp")))
	chk(truck.global_position.distance_to(froze) < 0.2, "这一秒车确实钉在原地")

	# ---- 10. 狗奶不受牵连 ----
	player.call("_exit_arena")
	await _frames(4)
	var milk: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "dogmilk":
			milk = b
	chk(milk != null and bool(milk.call("has_skills")), "狗奶仍是技能档")
	chk(milk != null and bool(milk.get("_faces_player")), "狗奶车头仍跟着玩家转")
	chk(milk != null and float(milk.get("_charge_lock")) == 0.0, "狗奶没有冲撞这招")
	chk(milk != null and milk.get("_lane") == null, "狗奶不建预警带")
	_done()


func _done() -> void:
	print("\n== 冲撞自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
