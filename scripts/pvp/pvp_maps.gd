extends Object
class_name PvpMaps
## PVP 三张地图（全程序化，无外部素材依赖）：山地 / 空白 / 国道。
## 每张图负责：地面、边界墙（物理墙，谁也出不去）、光照、以及 4 个出生点。
## build() 返回出生点数组（大厅座次顺序取用）。
const SIZE := 60.0          # 空白/国道的半边长
const ROAD_HALF_W := 11.0   # 国道半宽
const MOUNTAIN_SEED := 20260906   # 联机山地固定种子：各端复用单机地形系统生成同一片山
static func build(map_name: String, root: Node) -> Array:
	match map_name:
		"山地":
			return await _mountain(root)   # 地形要等网格就绪，build 整体变成协程
		"国道":
			return _road(root)
		_:
			return _blank(root)
static func _env(root: Node, top := Color(0.32, 0.52, 0.86), horizon := Color(0.92, 0.88, 0.80)) -> void:
	var owe := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = top
	psm.sky_horizon_color = horizon
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	owe.environment = env
	root.add_child(owe)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root.add_child(sun)
static func _box(root: Node, size: Vector3, pos: Vector3, col: Color,
		with_body := true, rough := 0.9) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	mi.material_override = m
	mi.position = pos
	root.add_child(mi)
	if with_body:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.add_child(cs)
		mi.add_child(sb)
	return mi
static func _wall_ring(root: Node, half: float, height := 6.0) -> void:
	var t := 1.0
	var col := Color(0.4, 0.42, 0.48, 1.0)
	_box(root, Vector3(half * 2.0 + t * 2.0, height, t), Vector3(0, height / 2.0, -half), col)
	_box(root, Vector3(half * 2.0 + t * 2.0, height, t), Vector3(0, height / 2.0, half), col)
	_box(root, Vector3(t, height, half * 2.0 + t * 2.0), Vector3(-half, height / 2.0, 0), col)
	_box(root, Vector3(t, height, half * 2.0 + t * 2.0), Vector3(half, height / 2.0, 0), col)
static func _blank(root: Node) -> Array:
	_env(root, Color(0.55, 0.62, 0.72), Color(0.95, 0.95, 0.97))
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE * 2.0, SIZE * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.96, 0.96, 0.97)
	m.roughness = 0.95
	pm.material = m
	root.add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE * 2.0, 1.0, SIZE * 2.0)
	cs.shape = shape
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	mi.add_child(sb)
	# 几个挡视野的白色方碑
	for i in 5:
		var ang := TAU * float(i) / 5.0 + 0.4
		_box(root, Vector3(3.0, 4.0, 1.2), Vector3(cos(ang) * 24.0, 2.0, sin(ang) * 24.0), Color(0.88, 0.88, 0.92))
	_wall_ring(root, SIZE - 1.0)
	return [Vector3(-20, 1.2, -20), Vector3(20, 1.2, -20), Vector3(-20, 1.2, 20), Vector3(20, 1.2, 20)]
static func _mountain(root: Node) -> Array:
	## 山地 = 直接复用单机的程序化地形系统：terrain.gd（PlaneMesh+shader 顶点位移、
	## 三角汤碰撞、边界墙）+ ground_detail.gd（石子装饰），不再自己拼网格。
	_env(root)
	# 菜单"新游戏"的 pending_seed 优先级更高，先清成"无指定"，再用固定种子保证各端同一片山
	SaveManager.pending_seed = -1
	var ground: Node3D = (load("res://scripts/terrain.gd") as GDScript).new()
	ground.name = "Ground"
	ground.seed_value = MOUNTAIN_SEED
	root.add_child(ground)
	var detail := Node3D.new()
	detail.name = "GroundDetail"
	detail.set_script(load("res://scripts/ground_detail.gd"))
	root.add_child(detail)
	# 等高度网格就绪（surface_height 才有准头；碰撞在 terrain 自己的物理帧后建）
	var tree := root.get_tree()
	for _i in 900:
		await tree.process_frame
		if bool(ground.call("grid_ready")):
			break
	var out: Array = []
	for k in 4:
		var ang := TAU * float(k) / 4.0 + PI / 4.0
		var x := cos(ang) * 34.0
		var z := sin(ang) * 34.0
		out.append(Vector3(x, float(ground.call("surface_height", x, z)) + 1.5, z))
	return out
static func _road(root: Node) -> Array:
	_env(root)
	var length := 120.0
	# 路面
	_box(root, Vector3(ROAD_HALF_W * 2.0, 0.4, length), Vector3(0, -0.2, 0), Color(0.32, 0.32, 0.34))
	# 草地两侧
	_box(root, Vector3(60.0, 0.4, length), Vector3(-ROAD_HALF_W - 30.0, -0.35, 0), Color(0.4, 0.55, 0.3), false)
	_box(root, Vector3(60.0, 0.4, length), Vector3(ROAD_HALF_W + 30.0, -0.35, 0), Color(0.4, 0.55, 0.3), false)
	# 车道虚线（装饰）
	for i in 14:
		_box(root, Vector3(0.25, 0.42, 3.0), Vector3(0, 0.02, -length / 2.0 + 4.0 + float(i) * 8.0),
			Color(0.9, 0.85, 0.4), false)
	# 两侧护栏（物理墙）：出不了国道
	_box(root, Vector3(0.8, 1.2, length), Vector3(-ROAD_HALF_W - 0.4, 0.6, 0), Color(0.75, 0.75, 0.78))
	_box(root, Vector3(0.8, 1.2, length), Vector3(ROAD_HALF_W + 0.4, 0.6, 0), Color(0.75, 0.75, 0.78))
	# 两端也堵上
	_box(root, Vector3(ROAD_HALF_W * 2.0 + 2.0, 1.2, 0.8), Vector3(0, 0.6, -length / 2.0), Color(0.75, 0.75, 0.78))
	_box(root, Vector3(ROAD_HALF_W * 2.0 + 2.0, 1.2, 0.8), Vector3(0, 0.6, length / 2.0), Color(0.75, 0.75, 0.78))
	# 路中两辆车当掩体
	_box(root, Vector3(2.2, 1.4, 5.0), Vector3(-3.0, 0.7, -18.0), Color(0.76, 0.09, 0.02))
	_box(root, Vector3(2.2, 1.4, 5.0), Vector3(3.0, 0.7, 16.0), Color(0.16, 0.35, 0.7))
	return [Vector3(-5, 1.2, -40), Vector3(5, 1.2, -40), Vector3(-5, 1.2, 40), Vector3(5, 1.2, 40)]
