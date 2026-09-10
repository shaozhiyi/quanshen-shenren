extends SceneTree
## 随机地形数值自检（headless）：多种子下的地形差异、BOSS 落点约束、碰撞与高度场一致性

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _initialize() -> void:
	print("== 随机地形自检 ==")
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _make_world(fixed_seed: int) -> Node:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	var ground := w.get_node("Ground")
	ground.set("seed_value", fixed_seed)
	root.add_child(w)
	return w


func _run() -> void:
	var sigs: Array = []
	for s in 6:
		var w := _make_world(1000 + s * 4637)
		await _frames(6)   # 等地形碰撞网格（物理帧后创建）就绪
		var ground := w.get_node("Ground")
		var player := w.get_node("Player")
		var list: Array = player.call("bosses")
		var boss: Node = list[0] if list.size() > 0 else null

		var amp: float = ground.get("height_amp")
		var freq: float = ground.get("frequency")
		var ts: int = ground.get("terrain_seed")
		print("  —— 种子 %d：amp=%.2f freq=%.5f" % [ts, amp, freq])
		chk(abs(amp - 13.0) > 0.01 or abs(freq - 0.009) > 1e-6, "种子 %d 的起伏参数已随机化" % ts)

		# 高度场：本局签名（5 个采样点）
		var sig: Array = []
		for i in 5:
			sig.append(round(ground.call("height_at", float(i) * 61.0 - 120.0, float(i) * 43.0 - 90.0) * 100.0) / 100.0)
		sigs.append(sig)
		print("     采样高度 %s" % str(sig))
		var hmin := 1e9
		var hmax := -1e9
		for iz in 24:
			for ix in 24:
				var hv: float = ground.call("height_at", -200.0 + float(ix) * 17.0, -200.0 + float(iz) * 17.0)
				hmin = minf(hmin, hv)
				hmax = maxf(hmax, hv)
		chk(hmax - hmin > 12.0, "起伏跨度足够大（%.1f 米）" % (hmax - hmin))
		# 局部起伏：玩家出生点周围 80 米内必须看得见山丘（不要整片平原）
		var sp0: Vector3 = w.get_node("Player").get("global_position")
		var lmin := 1e9
		var lmax := -1e9
		for iz in 12:
			for ix in 12:
				var lx: float = sp0.x - 80.0 + float(ix) * 14.5
				var lz: float = sp0.z - 80.0 + float(iz) * 14.5
				var lh: float = ground.call("height_at", lx, lz)
				lmin = minf(lmin, lh)
				lmax = maxf(lmax, lh)
		chk(lmax - lmin >= 5.0, "出生点周围 80 米内起伏 %.1f 米（不会开局一片平原）" % (lmax - lmin))

		# BOSS 落点约束：距离带 / 坡度 / 边界 / 贴地
		var bp: Vector3 = boss.get("position")
		var sp: Vector3 = player.get("global_position")
		var d := sqrt((bp.x - sp.x) * (bp.x - sp.x) + (bp.z - sp.z) * (bp.z - sp.z))
		chk(d >= 30.0 and d <= 70.0, "BOSS 水平距离 %.1f 米（要求 30~70，不会生成太远）" % d)
		var n: Vector3 = ground.call("normal_at", bp.x, bp.z)
		chk(n.y >= 0.93, "BOSS 落点坡度平缓（法线 y=%.3f）" % n.y)
		chk(abs(bp.x) < 195.0 and abs(bp.z) < 195.0, "BOSS 在地形内部安全区 (%.1f, %.1f)" % [bp.x, bp.z])
		chk(abs(bp.y - ground.call("height_at", bp.x, bp.z)) < 0.01, "BOSS 精确贴地")
		chk(boss.get("_home_pos") != null and bp.distance_to(boss.get("_home_pos")) < 0.01, "回家点已同步到新落点")

		# 碰撞体与解析高度场一致性：从高空向下打射线
		var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
		var max_err := 0.0
		var samples := 0
		for i in 25:
			var x := -200.0 + float(i % 5) * 100.0
			var z := -200.0 + float(i / 5) * 100.0
			var he: float = ground.call("height_at", x, z)
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, he + 12.0, z), Vector3(x, he - 12.0, z))
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			samples += 1
			max_err = maxf(max_err, abs(float(hit.position.y) - he))
		chk(samples >= 23, "射线采样到 %d/25 个地面点" % samples)
		chk(max_err < 1.6, "碰撞面与高度场最大偏差 %.2f 米（格距 3.9 米的线性近似容差内）" % max_err)

		# 出生点站得住：脚下 12 米内必须有地面
		var q2 := PhysicsRayQueryParameters3D.create(sp + Vector3(0, 6, 0), sp - Vector3(0, 20, 0))
		q2.exclude = [player.get_rid()]
		var hit2 := space.intersect_ray(q2)
		chk(not hit2.is_empty(), "出生点下方有可站立地面")
		if not hit2.is_empty():
			chk(sp.y - float(hit2.position.y) < 4.0, "出生点未悬空（离地 %.1f 米）" % (sp.y - float(hit2.position.y)))

		w.queue_free()
		await _frames(2)

	# 三个种子必须给出不同地形
	var differ := true
	for i in sigs[0].size():
		if abs(float(sigs[0][i]) - float(sigs[1][i])) < 0.01 and abs(float(sigs[1][i]) - float(sigs[2][i])) < 0.01:
			differ = false
	chk(differ, "不同种子生成不同地形（同点高度三局互异）")

	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)
