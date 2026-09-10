extends SceneTree
## 石子贴地 + 全图覆盖自检。
##
## 存在理由：用户反馈"石子全部悬空了"。根因是石头按 terrain.height_at()（解析式噪声）
## 摆高度，而地面 mesh 是 128 段（3.9 米一格）的顶点网格 + shader 位移，高频倍频根本没
## 被采到 —— 解析值与真正铺出来的地面平均差 0.13 米、最大差 0.85 米，于是石头整片飘着。
## 这份自检不信任何一侧的算法：直接向下打物理射线问"地面到底在哪"，逐颗核对。
## 走的是菜单 → 分帧进场景 → 分片建碰撞的真实链路（贴物要等高度网格就绪）。
##
## 注：MultiMesh 的实例数据在 GDScript 侧只写不读（get_instance_transform 恒返回单位阵），
## 所以核对的是 ground_detail.rock_layout() 这份布局；"有没有真挂上去"由截图确认。

var fails: Array[String] = []

const BUCKETS := 8              # 覆盖度分格：8×8 都要有石头才算"铺满全图"


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _idle(n: int) -> void:
	for _i in n:
		await process_frame


func _find_root(nm: String) -> Node:
	for c in root.get_children():
		if String(c.name) == nm:
			return c
	return null


func _run() -> void:
	SaveManager.stage_new_game(20260905)
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await _idle(20)
	menu.call("_on_new_game")
	var w: Node = await _wait_main(900)
	if w == null:
		chk(false, "没能切进游戏场景")
		_done()
		return
	await _idle(30)
	var ground: Node = w.get_node("Ground")
	var details: Node = w.get_node("GroundDetails")

	# ---- 0. 前置：高度网格就绪、石子真的挂到了树上 ----
	chk(bool(ground.call("grid_ready")), "地形高度网格已就绪（贴物的前提）")
	var tiles: Array = []
	for _i in 600:
		tiles.clear()
		for c in details.get_children():
			if c.get("multimesh") != null:
				tiles.append(c)
		if not tiles.is_empty():
			break
		await process_frame
	chk(tiles.size() > 0, "石子已挂上场景树")
	if tiles.is_empty():
		_done()
		return
	var layout: Array[Transform3D] = details.call("rock_layout", ground)
	var count: int = layout.size()
	var total := 0
	var no_range := 0
	for c in tiles:
		total += int((c.get("multimesh") as MultiMesh).instance_count)
		if float(c.get("visibility_range_end")) <= 0.0:
			no_range += 1
	chk(tiles.size() > 1, "石子拆成 %d 个地块（整图一块的话无法逐块剔除）" % tiles.size())
	chk(no_range == 0, "每个地块都设了距离剔除上限（没设的 %d 块）" % no_range)
	chk(total == count,
		"各地块实例数加总 = 布局数（%d 颗，旧版只撒 700 颗在中央 240×240）" % total)
	print("     （地图 %.0f×%.0f 米，石子 %d 颗 / %d 块）" % [
		float(ground.get("size")), float(ground.get("size")), count, tiles.size()])

	# ---- 1. 全图覆盖 ----
	var half: float = float(ground.get("size")) * 0.5
	var grid := {}
	var minx := 1e9
	var maxx := -1e9
	var minz := 1e9
	var maxz := -1e9
	var outside := 0
	for t in layout:
		var x: float = t.origin.x
		var z: float = t.origin.z
		minx = minf(minx, x); maxx = maxf(maxx, x)
		minz = minf(minz, z); maxz = maxf(maxz, z)
		if absf(x) > half or absf(z) > half:
			outside += 1
		var bx := clampi(int((x + half) / (half * 2.0) * BUCKETS), 0, BUCKETS - 1)
		var bz := clampi(int((z + half) / (half * 2.0) * BUCKETS), 0, BUCKETS - 1)
		var key := "%d_%d" % [bx, bz]
		grid[key] = int(grid.get(key, 0)) + 1
	var missing := 0
	for bx in BUCKETS:
		for bz in BUCKETS:
			if not grid.has("%d_%d" % [bx, bz]):
				missing += 1
	chk(missing == 0, "地图 %d×%d 分格每格都有石子（空格 %d 个）" % [BUCKETS, BUCKETS, missing])
	chk(minx < -half + 25.0 and maxx > half - 25.0 and minz < -half + 25.0 and maxz > half - 25.0,
		"石子铺到地图边缘（x %.0f~%.0f，z %.0f~%.0f，地图半宽 %.0f）" % [minx, maxx, minz, maxz, half])
	chk(outside == 0, "没有石子撒到地形范围外（越界 %d 颗）" % outside)

	# ---- 2. 逐颗核对贴地：向下射线问真正的地面 ----
	var space: PhysicsDirectSpaceState3D = ground.get_world_3d().direct_space_state
	var floating := 0
	var no_hit := 0
	var checked := 0
	var max_float := -1e9
	var buried_more_than_half := 0
	var old_would_float := 0            # 诊断：旧写法（解析高度）会飘多少
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var sample: int = mini(count, 500)
	for k in sample:
		var i := 0 if k == 0 else rng.randi_range(0, count - 1)
		var t: Transform3D = layout[i]
		var sy: float = t.basis.get_scale().y
		var q := PhysicsRayQueryParameters3D.new()
		q.from = Vector3(t.origin.x, t.origin.y + 3.0, t.origin.z)
		q.to = Vector3(t.origin.x, t.origin.y - 3.0, t.origin.z)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty() or (hit["collider"] as Node).get_parent() != ground:
			no_hit += 1
			continue
		checked += 1
		var d: float = (hit["position"] as Vector3).y - t.origin.y   # >0 = 埋进地里（种住了）
		max_float = maxf(max_float, -d)
		if d < -0.005:
			floating += 1
		if d > sy * 0.5:
			buried_more_than_half += 1
		var an: float = ground.call("height_at", t.origin.x, t.origin.z)
		if an - (hit["position"] as Vector3).y > 0.1:
			old_would_float += 1
	chk(no_hit < sample * 0.05,
		"射线能问到底面（%d/%d 没命中地面，多为 BOSS 身体等遮挡）" % [no_hit, sample])
	chk(checked > 300, "真正核对到的石子数量够用（%d 颗）" % checked)
	chk(floating == 0, "没有一颗石子悬空（浮起最大 %.3f 米，负数=最浅的一颗也埋进地面这么多）" % max_float)
	chk(buried_more_than_half == 0,
		"石子也没整颗埋没（埋过自身半高的 %d 颗，露出部分看得见）" % buried_more_than_half)
	print("     （对照：同样这些位置用旧的解析高度摆，会有 %.1f%% 浮空 >0.1 米）"
		% (100.0 * old_would_float / maxi(checked, 1)))

	# ---- 3. surface_height 与真碰撞面一致（slam_fx、放 BOSS 都靠它）----
	var max_dev := 0.0
	var max_bilinear := 0.0
	for _i in 300:
		var x := rng.randf_range(-half + 6.0, half - 6.0)
		var z := rng.randf_range(-half + 6.0, half - 6.0)
		var sh: float = ground.call("surface_height", x, z)
		var q := PhysicsRayQueryParameters3D.new()
		q.from = Vector3(x, sh + 6.0, z)
		q.to = Vector3(x, sh - 6.0, z)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty() or (hit["collider"] as Node).get_parent() != ground:
			continue
		max_dev = maxf(max_dev, absf((hit["position"] as Vector3).y - sh))
		max_bilinear = maxf(max_bilinear, absf(ground.call("height_at_fast", x, z) - sh))
	chk(max_dev < 0.02, "surface_height 与真碰撞面严格一致（最大偏差 %.4f 米）" % max_dev)
	print("     （双线性采样 height_at_fast 与三角插值最大差 %.3f 米，只用于小地图概览）" % max_bilinear)

	# ---- 4. 视觉面与碰撞面必须沿同一条对角线剖分，否则贴物仍会露缝 ----
	chk(_plane_uses_anti_diag(),
		"PlaneMesh 的剖分对角线与 _fill_grid_tris 一致（换向会让石子露出最多 0.26 米的缝）")

	# ---- 5. 大地图上的 BOSS 也坐在地面上，不是飘着 ----
	var bosses: Array = get_nodes_in_group("boss_unit")
	chk(bosses.size() > 0, "名册 BOSS 都在大地图上")
	for b in bosses:
		var bx: float = b.get("world_x")
		var bz: float = b.get("world_z")
		var want: float = ground.call("surface_height", bx, bz)
		var got: float = (b as Node).global_position.y
		chk(absf(got - want) < 0.02,
			"%s 落座贴合地面（%.2f vs 地面 %.2f，差 %.3f 米）" % [
				String(b.get("boss_name")), got, want, got - want])
	_done()


func _plane_uses_anti_diag() -> bool:
	## 读 PlaneMesh 的索引缓冲，看每个方格沿哪条对角线剖开：
	## 三角形里"两个顶点 x、z 都不同"的那条边就是对角线。
	## 与 terrain._fill_grid_tris 用的 (x1,z0)-(x0,z1)（dx、dz 反号）一致才算对齐。
	var plane := PlaneMesh.new()
	plane.size = Vector2(500.0, 500.0)
	plane.subdivide_width = 128
	plane.subdivide_depth = 128
	var arr: Array = plane.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for tri in mini(idx.size() / 3, 8):
		var p: Array[Vector3] = []
		for c in 3:
			p.append(verts[idx[tri * 3 + c]])
		for a in 3:
			var b := (a + 1) % 3
			var dx: float = p[b].x - p[a].x
			var dz: float = p[b].z - p[a].z
			if absf(dx) > 0.01 and absf(dz) > 0.01:
				return dx * dz < 0.0        # 反号 = 与碰撞面同一条副对角线
	return false


func _wait_main(limit: int) -> Node:
	for _i in limit:
		await process_frame
		var w := _find_root("Main")
		if w != null:
			return w
	return null


func _done() -> void:
	print("\n== 石子自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
