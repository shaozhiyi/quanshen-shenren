extends Object
class_name PvpMaps
## PVP 三张地图（全程序化，无外部素材依赖）：山地 / 空白 / 国道。
## 每张图负责：地面、边界墙（物理墙，谁也出不去）、光照、以及 4 个出生点。
## build() 返回出生点数组（大厅座次顺序取用）。

const SIZE := 60.0          # 山地/空白的半边长
const ROAD_HALF_W := 11.0   # 国道半宽


static func build(map_name: String, root: Node) -> Array:
	match map_name:
		"山地":
			return _mountain(root)
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
	_env(root)
	var N := 96
	var half := SIZE
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0, half * 2.0)
	pm.subdivide_depth = N
	pm.subdivide_width = N
	var noise := FastNoiseLite.new()
	noise.seed = 20260906
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var mesh: Mesh = pm.get_mesh()
	if mesh != null:
		var arrays: Array = mesh.get_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var v := verts[i]
			var d := Vector2(v.x, v.z).length() / half
			var h := noise.get_noise_2d(v.x, v.z) * 10.0
			var flat := clampf((d - 0.28) / 0.4, 0.0, 1.0)   # 半径 28% 以内是平地
			v.y = h * flat * flat + (1.0 - flat) * 0.0 + flat * 6.0
			verts[i] = v
		arrays[Mesh.ARRAY_VERTEX] = verts
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.55, 0.32)
		m.roughness = 0.95
		am.surface_set_material(0, m)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		root.add_child(mi)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = am.create_trimesh_shape()
		sb.add_child(cs)
		mi.add_child(sb)
	# 几块大石头当掩体
	var rock_col := Color(0.5, 0.5, 0.52)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		_box(root, Vector3(3.0, 2.4, 2.2), Vector3(cos(ang) * 18.0, 1.2, sin(ang) * 18.0), rock_col)
	_wall_ring(root, half - 1.0, 8.0)
	return [Vector3(-14, 1.2, -14), Vector3(14, 1.2, -14), Vector3(-14, 1.2, 14), Vector3(14, 1.2, 14)]


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
