extends SceneTree
## R13 无头自检：给「国道」加的战场限制
##  1) 无法离开国道：highway.confine() 把玩家横向夹在右幅车道内，纯白空间与大地图不受影响；
##     玩家在空间内每帧真的会被夹回去（沿 z 仍然自由）
##  2) 两套空间的 confine 接口都在，且语义正确（纯白 = 恒等）
##  3) 名册字段接线正确（狗奶没有冲撞/载具档那一套）
## 大运「锁定冲撞」本身（不转向 / 逐帧推进 / 撞击伤害 / 红色路径预警带）见 charge_selftest.gd

var fails: Array[String] = []


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


func _run() -> void:
	var ROSTER: GDScript = load("res://scripts/boss_roster.gd")

	# ---- 1. 名册接线 ----
	var dtruck: Dictionary = ROSTER.def("truck")
	var dmilk: Dictionary = ROSTER.def("dogmilk")
	chk(absf(float(dtruck.get("charge_lock", 0.0)) - 2.0) < 0.001, "名册：大运锁定预警 = 2 秒")
	chk(absf(float(dtruck.get("charge_units", 0.0)) - 8.0) < 0.001, "名册：撞击行程 = 8 个冲刺距离")
	chk(float(dtruck.get("charge_gap", 0.0)) > 0.0, "名册：撞完有冷却")
	chk(float(dmilk.get("charge_lock", 0.0)) == 0.0, "名册：狗奶没配冲撞")

	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 88102)
	root.add_child(w)
	await _frames(25)
	var player := w.get_node("Player")
	var arenas := _arenas()
	var hw: Node = arenas.get("highway")
	var wht: Node = arenas.get("white")
	chk(hw != null and wht != null, "场景里两套空间都在")

	# ---- 2. confine 接口：纯白恒等，国道夹在右幅车道 ----
	chk(wht.has_method("confine") and hw.has_method("confine"), "两套空间都实现了 confine()")
	var probe := Vector3(123.0, 4.5, -67.0)
	chk(wht.call("confine", probe) == probe, "纯白空间不夹人（恒等返回）")
	var c: Vector3 = hw.call("center")
	# 常量不能靠 get() 读，改用 confine() 探两个极端反推横界
	var hi: float = float((hw.call("confine", Vector3(c.x + 1e6, 101.0, c.z)) as Vector3).x) - c.x
	var lo: float = float((hw.call("confine", Vector3(c.x - 1e6, 101.0, c.z)) as Vector3).x) - c.x
	chk(lo > 3.5 and lo < 6.0 and hi > 16.0 and hi < 19.0,
		"可行走横界在隔离带与路肩护栏之间（%.1f ~ %.1f）" % [lo, hi])
	var far_out: Vector3 = hw.call("confine", Vector3(c.x + 900.0, 101.0, c.z))
	var in_med: Vector3 = hw.call("confine", Vector3(c.x - 2.0, 101.0, c.z))
	var legal: Vector3 = hw.call("confine", Vector3(c.x + 12.5, 101.0, c.z))
	chk(absf(far_out.x - (c.x + hi)) < 0.001, "越出路肩 → 夹到外护栏内侧")
	chk(absf(in_med.x - (c.x + lo)) < 0.001, "压进隔离带 → 夹回车道内侧")
	chk(absf(legal.x - (c.x + 12.5)) < 0.001, "本来就在车道里 → 一动不动")
	chk(absf(far_out.z - c.z) < 0.001, "沿路方向（z）不受限")

	# ---- 3. 进战后玩家真的被夹住 ----
	var truck: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "truck":
			truck = b
	chk(truck != null, "找到大运")
	if truck == null:
		_done()
		return
	# 进战前得先站到它旁边，否则 _enter_arena 找不到"要开战的 BOSS"会直接返回
	player.global_position = Vector3(truck.global_position.x, truck.global_position.y + 1.0,
		truck.global_position.z + 8.0)
	await _frames(2)
	player.call("_enter_arena")
	await _frames(8)
	chk(bool(player.call("in_arena")), "已进国道空间")
	chk(bool(hw.call("is_active")), "国道空间已激活")
	var spawn: Vector3 = player.global_position
	chk(absf(spawn.x - 12.5) < 0.6, "出生点就在右幅车道上（x=%.1f）" % spawn.x)
	# 夹取是玩家自己每帧做的，所以这里必须让它活着跑物理
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.global_position = Vector3(c.x + 60.0, spawn.y, c.z)
	await _frames(4)
	chk(player.global_position.x <= c.x + hi + 0.05,
		"把人丢到路外 → 逐帧被夹回路肩（x=%.1f）" % player.global_position.x)
	player.global_position = Vector3(c.x - 30.0, spawn.y, c.z + 40.0)
	var keep_z: float = player.global_position.z
	await _frames(4)
	chk(player.global_position.x >= c.x + lo - 0.05,
		"压进隔离带也会被夹回（x=%.1f）" % player.global_position.x)
	chk(absf(player.global_position.z - keep_z) < 0.5, "顺路前后跑不受限（z 保持）")

	# ---- 4. 狗奶那套循环没被牵连 ----
	player.call("_exit_arena")
	await _frames(4)
	var milk: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "dogmilk":
			milk = b
	chk(milk != null and bool(milk.call("has_skills")), "狗奶仍是技能档")
	chk(float(milk.get("_charge_lock")) == 0.0, "狗奶没配冲撞（也不建预警带）")
	_done()


func _done() -> void:
	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
