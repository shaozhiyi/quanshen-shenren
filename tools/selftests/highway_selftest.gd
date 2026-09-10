extends SceneTree
## 大运国道战斗空间的无头自检：
##  1) 两套空间（纯白 / 国道）并列存在、API 一致、名册按 BOSS 指定用哪一套
##  2) 进入重卡空间：玩家与重卡都落在同一条车行道上，白空间保持隐藏，环境切换
##  3) 国道几何齐全：两条车行道 + 标线 + 隔离带护栏 + 路灯 + 电线杆 + 龙门架，
##     且"无限"靠雾 + MultiMesh + 池化灯光（灯永远吸附在玩家附近几盏）
##  4) 星点落地判定要认对空间（在国道里用国道地板，在大地图里用地形）
##  5) 离开空间一切还原

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


func _count_meshes(root: Node, cls: String) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for c in nd.get_children():
			if c.get_class() == cls:
				n += 1
			stack.append(c)
	return n


func _run() -> void:
	var BS: GDScript = load("scripts/boss.gd")
	var ROSTER: GDScript = load("scripts/boss_roster.gd")

	# ---- 1. 名册接线 ----
	var dtruck: Dictionary = ROSTER.def("truck")
	var dmilk: Dictionary = ROSTER.def("dogmilk")
	chk(String(dtruck.get("arena", "")) == "highway", "名册：重卡 → 大运国道空间")
	chk(String(dmilk.get("arena", "white")) == "white", "名册：狗奶仍用纯白空间（不写=默认）")

	# ---- 2. 场景里有两套空间且 API 一致 ----
	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 88001)
	root.add_child(w)
	await _frames(25)
	var amap := _arenas()
	chk(amap.has("white") and amap.has("highway"), "两套空间都在 arena 分组里（%s）" % str(amap.keys()))
	var hw: Node = amap.get("highway")
	var wh: Node = amap.get("white")
	if hw == null or wh == null:
		_done()
		return
	var need := ["floor_y", "inside", "set_active", "is_active", "center", "bounds_half",
		"player_spawn", "boss_spawn", "set_day_night", "theme_key"]
	var missing: Array = []
	for m in need:
		if not hw.has_method(m):
			missing.append(m)
	chk(missing.is_empty(), "国道空间 API 与纯白空间一致（缺 %s）" % str(missing))
	chk(hw.get("arena_env") is Environment, "国道空间自带 Environment（进战时替换大地图）")
	chk(not bool(hw.call("is_active")) and not bool(wh.call("is_active")), "开局两套空间都未激活")
	var hwc: Vector3 = hw.call("center")
	chk(absf(hwc.y - float(wh.call("floor_y"))) < 0.001, "两套空间同一高度（y=100），星点判定才不会串")
	chk(hwc.distance_to(wh.call("center")) > 1000.0, "两套空间在世界上互相隔开（不会重叠）")
	chk(bool(hw.call("inside", hwc + Vector3(0, 100, 0))), "inside() 认自己范围内的点")
	chk(not bool(hw.call("inside", wh.call("center"))), "inside() 不把别的空间里的点算进来")

	# ---- 3. 雾与几何：无限延伸的底气 ----
	var env: Environment = hw.get("arena_env")
	chk(env.fog_enabled and env.fog_density > 0.003, "开了浓雾（density=%.4f）→ 看不见路尾" % env.fog_density)
	chk(absf(float(hw.call("bounds_half")) - 400.0) < 1.0, "地板半宽 400 米")
	chk(_count_meshes(hw, "MeshInstance3D") >= 12, "路面/标线/隔离带/龙门架等实体面片 %d 个"
		% _count_meshes(hw, "MeshInstance3D"))
	chk(_count_meshes(hw, "MultiMeshInstance3D") >= 4, "护栏桩/灯杆/灯头/电线杆走 MultiMesh（%d 组）"
		% _count_meshes(hw, "MultiMeshInstance3D"))
	var heads: PackedVector3Array = hw.get("_lamp_heads")
	chk(heads.size() >= 20, "沿路布了 %d 个灯头（间距 32 米）" % heads.size())
	var lamps: Array = hw.get("_lamps")
	chk(lamps.size() == 4, "池化光源 4 盏（不是一灯一盏灯堆出来的）")
	# 车道中心线在 x=±9.5，两侧都要有
	var spawns: Vector3 = hw.call("player_spawn")
	var bspawn: Vector3 = hw.call("boss_spawn")
	chk(absf(spawns.x - hwc.x - 12.5) < 0.01, "玩家出生点在右侧行车道中心（x=%.1f，不压虚线）" % (spawns.x - hwc.x))
	chk(absf(bspawn.x - spawns.x) < 0.01, "重卡出生点与玩家同一条车道（沿路对开）")
	chk(bspawn.z < spawns.z, "重卡在玩家前方 %d 米处" % int(spawns.z - bspawn.z))

	# ---- 4. 进入重卡空间 ----
	var player: Node = w.get_node("Player")
	var truck: Node = null
	var milk: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "truck":
			truck = b
		if String(b.get("def_id")) == "dogmilk":
			milk = b
	chk(truck != null and milk != null, "两只 BOSS 都在场")
	if truck == null:
		_done()
		return
	chk(String(truck.call("arena_name")) == "highway", "重卡报告自己的战场是 highway")
	chk(String(milk.call("arena_name")) == "white", "狗奶报告自己的战场是 white")

	player.global_position = Vector3(truck.global_position.x, truck.global_position.y + 1.0,
		truck.global_position.z + 8.0)
	await _frames(2)
	player.call("_enter_arena")
	await _frames(8)
	chk(bool(hw.call("is_active")), "进入重卡空间：国道激活")
	chk(not bool(wh.call("is_active")), "纯白空间保持隐藏（没被顺带打开）")
	chk(bool(player.call("in_arena")), "玩家已在空间内")
	var pp: Vector3 = player.global_position
	chk(absf(pp.x - hwc.x - 12.5) < 0.01, "玩家落在右侧行车道上（x=%.1f）" % (pp.x - hwc.x))
	chk(absf(pp.y - (hwc.y + 1.05)) < 0.6, "玩家站在国道地板上（y=%.1f）" % pp.y)
	var tp: Vector3 = truck.global_position
	chk(absf(tp.x - hwc.x - 12.5) < 0.01, "重卡也在同一条行车道上（x=%.1f）" % (tp.x - hwc.x))
	var owe: WorldEnvironment = w.get_node("WorldEnvironment")
	chk(owe.get("environment") == env, "世界环境已切到国道的黄昏 + 雾")
	var ground: Node = w.get_node("Ground")
	chk(not bool(ground.get("visible")), "大地图地形已隐藏（不会和路面穿模）")

	# 池化灯光吸附到玩家附近
	await _frames(5)
	var maxd := 0.0
	for om in lamps:
		maxd = maxf(maxd, (om as Node3D).global_position.distance_to(pp))
	chk(maxd < 60.0, "4 盏灯吸附到玩家附近（最远 %.1f 米）→ 跑到哪灯都在头顶" % maxd)

	# 重卡仍按名册行事：缓慢驶近 + 贴身尾气
	chk(float(truck.get("_chase_speed")) > 0.0, "重卡保持驶近行为（%.1f 米/秒）"
		% float(truck.get("_chase_speed")))
	var hp0: float = float(player.get("hp"))
	player.global_position = Vector3(tp.x, hwc.y + 1.05, tp.z + 5.0)
	await _frames(30)
	chk(float(player.get("hp")) < hp0, "贴到车身会吃到尾气掉血（%.1f → %.1f）"
		% [hp0, float(player.get("hp"))])
	chk(int(truck.get("_phase")) == 0 and get_nodes_in_group("slam_star").is_empty(),
		"重卡依旧不放技能（无星点、无砸地相位）")

	# ---- 5. 星点落地判定要认对空间 ----
	var FX: GDScript = load("res://scripts/slam_fx.gd")
	var fx: Node3D = FX.new()
	hw.add_child(fx)          # 借它的 _floor_y 做点采样（不真发射）
	var y_hw: float = fx.call("_floor_y", hwc + Vector3(9.5, 101.0, 0.0))
	chk(absf(y_hw - hwc.y) < 0.001, "国道空间内的点 → 地板 y=%.1f" % y_hw)
	var y_out: float = fx.call("_floor_y", Vector3(0.0, 500.0, 0.0))
	chk(y_out < 200.0, "空间外的点不会被误判成国道地板（返回 %.1f）" % y_out)
	fx.queue_free()

	# ---- 6. 夜里灯更亮（接口留着，之后重卡加技能可用）----
	var e_day: float = (lamps[0] as OmniLight3D).light_energy
	hw.call("set_day_night", 1.0)
	var e_night: float = (lamps[0] as OmniLight3D).light_energy
	chk(e_night > e_day, "set_day_night(1) 让路灯更亮（%.1f → %.1f）" % [e_day, e_night])
	hw.call("set_day_night", 0.0)

	# ---- 7. 离开空间一切还原 ----
	player.call("_exit_arena")
	await _frames(6)
	chk(not bool(hw.call("is_active")), "离开后国道空间收起")
	chk(not bool(player.call("in_arena")), "玩家已回到大地图")
	chk(bool(ground.get("visible")), "大地图地形恢复显示")
	chk(owe.get("environment") != env, "环境还原成大地图的")
	chk(not bool(truck.call("is_arena_mode")), "重卡退出应战状态（回大地图继续无敌）")

	# ---- 8. 狗奶仍然进纯白空间（老玩法不受影响）----
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0,
		milk.global_position.z + 8.0)
	await _frames(2)
	player.call("_enter_arena")
	await _frames(6)
	chk(bool(wh.call("is_active")) and not bool(hw.call("is_active")), "打狗奶仍进纯白空间")
	var mp: Vector3 = player.global_position
	chk(absf(mp.x - hwc.x) < 0.01, "纯白空间出生点仍在原点（x=%.1f）" % mp.x)
	player.call("_exit_arena")
	await _frames(4)

	_done()


func _done() -> void:
	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
