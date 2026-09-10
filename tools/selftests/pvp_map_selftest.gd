extends SceneTree
## PVP 山地地图自检（复用单机 terrain.gd 版）：①地形节点+碰撞建好 ②4 个出生点脚下有地面
## ③角色站上去不落穿 ④截屏肉眼复核。防"开局无限下落"回归。

const SHOT := "user://pvp_map_mountain.png"


func _idle(n: int) -> void:
	for _i in n:
		await physics_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	var fails := [0]
	var world := Node3D.new()
	root.add_child(world)
	await _idle(2)
	var spawns: Array = await PvpMaps.build("山地", world)
	await _idle(10)   # 等物理世界把碰撞建好

	var chk := func(ok: bool, tag: String) -> void:
		if ok:
			print("  ok  | ", tag)
		else:
			fails[0] += 1
			print("  FAIL| ", tag)

	chk.call(spawns.size() == 4, "4 个出生点")
	var ground_node := world.get_node_or_null("Ground")
	chk.call(ground_node != null, "单机地形节点 Ground 已挂上")
	chk.call(ground_node != null and bool(ground_node.call("grid_ready")), "高度网格就绪")

	var space := world.get_world_3d().direct_space_state
	var ray := func(from: Vector3) -> float:
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -400, 0))
		var hit := space.intersect_ray(q)
		return float(hit.position.y) if not hit.is_empty() else -999.0
	var ok_spawns := true
	for s in spawns:
		var g: float = ray.call(Vector3(s.x, s.y + 40.0, s.z))
		if g < -100.0 or absf(g - (s.y - 1.5)) > 0.6:
			ok_spawns = false
			print("   出生点 %s 脚下地面 y=%s（期望 %s）" % [str(s), str(g), str(s.y - 1.5)])
	chk.call(ok_spawns, "4 个出生点脚下都有地面且高度吻合")

	# 自由落体砸到地面：刚体 1 秒后应停在地面附近（不落穿、不悬空）
	var ground_node2 := world.get_node_or_null("Ground")
	var body := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	body.add_child(cs)
	body.position = spawns[0] + Vector3(0, 3.0, 0)
	body.contact_monitor = false
	world.add_child(body)
	await _idle(90)
	var surf: float = float(ground_node2.call("surface_height", spawns[0].x, spawns[0].z))
	chk.call(absf(body.global_position.y - surf) < 2.0,
		"从空中落稳在地面附近（y=%s 地面=%s）" % [str(snappedf(body.global_position.y, 0.01)), str(snappedf(surf, 0.01))])

	var cam := Camera3D.new()
	cam.position = spawns[0] + Vector3(0, 1.6, 0)
	cam.rotation_degrees = Vector3(-8, 135, 0)
	root.add_child(cam)
	cam.current = true
	await _idle(8)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(SHOT)
	print("SHOT:", SHOT)
	print("== 山地地图自检：", "0 项失败 ==" if fails[0] == 0 else "%d 项失败 ==" % fails[0])
	quit(0 if fails[0] == 0 else 1)
