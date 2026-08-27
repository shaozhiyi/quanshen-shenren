extends Node3D
## 程序化起伏地形：fbm 高度场生成网格；碰撞用三角网格（ConcavePolygonShape3D）贴合地形。
## 物理体必须在物理帧之后创建，场景加载期创建的碰撞体不会被物理世界接收。

@export var size := 500.0
@export var segments := 128
@export var height_amp := 13.0
@export var frequency := 0.009

const GROUND_SHADER := preload("res://shaders/ground.gdshader")

# 碰撞构建时缓存的高度网格（供 height_at_fast）
var _grid: PackedFloat32Array
var _grid_n := 0
var _grid_half := 0.0
var _grid_cell := 1.0


func _ready() -> void:
	# mesh 立即生成（渲染需要）；物理体延迟到第一个物理帧创建
	_build_terrain_mesh()
	await get_tree().physics_frame
	_build_collision()
	_build_boundary_walls()


# ---- 公共高度查询：草/杂物用它贴合地表 ----
func height_at(x: float, z: float) -> float:
	return _height_at(x, z)


func height_at_fast(x: float, z: float) -> float:
	## 双线性采样缓存高度网格（微秒级），供小地图等概览用途；
	## 网格未就绪（碰撞构建前）时回退解析式。
	if _grid.is_empty():
		return _height_at(x, z)
	var fx := (x + _grid_half) / _grid_cell
	var fz := (z + _grid_half) / _grid_cell
	fx = clampf(fx, 0.0, float(_grid_n - 1) - 0.001)
	fz = clampf(fz, 0.0, float(_grid_n - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var r0 := iz * _grid_n + ix
	var r1 := r0 + _grid_n
	var h00: float = _grid[r0]
	var h10: float = _grid[r0 + 1]
	var h01: float = _grid[r1]
	var h11: float = _grid[r1 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	## 地表法线（中心差分，与 shader 顶点法线同公式），供草/杂物沿坡倾斜
	var e := 0.5
	var h := _height_at(x, z)
	var hx := _height_at(x + e, z)
	var hz := _height_at(x, z + e)
	return Vector3(h - hx, e, h - hz).normalized()


func _height_at(x: float, z: float) -> float:
	var n := _fbm(Vector2(x, z) * frequency)
	var n2 := _fbm(Vector2(x, z) * frequency * 4.0 + Vector2(17.0, 3.0))
	var n3 := _fbm(Vector2(x, z) * frequency * 6.0 + Vector2(7.0, 11.0))
	return (n * 0.75 + n2 * 0.25 + n3 * 0.12) * height_amp * 2.0 - height_amp


func _build_terrain_mesh() -> void:
	# 注意：大 ArrayMesh 在本机环境渲染有 bug（顶点数多时整个 mesh 不可见），
	# 地面改用 PlaneMesh（PrimitiveMesh 渲染正常）+ shader 顶点位移生成起伏。
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = segments
	plane.subdivide_depth = segments

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("height_amp", height_amp)
	mat.set_shader_parameter("frequency", frequency)
	mat.set_shader_parameter("height_step", size / float(segments))
	mat.set_shader_parameter("albedo_tex", load("res://assets/ground/leafy_grass_diff_2k.jpg"))
	mat.set_shader_parameter("normal_tex", load("res://assets/ground/leafy_grass_nor_gl_2k.jpg"))
	mat.set_shader_parameter("rough_tex", load("res://assets/ground/leafy_grass_rough_2k.jpg"))
	plane.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = plane
	add_child(mi)


func _build_collision() -> void:
	## 地形碰撞：三角网格（ConcavePolygonShape3D）采样同一高度场。
	## 起伏变大后 Box 网格近似会形成台阶卡住玩家，trimesh 在物理帧后创建已验证稳定。
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_build_collision_faces())
	var body := StaticBody3D.new()
	var csc := CollisionShape3D.new()
	csc.shape = shape
	body.add_child(csc)
	add_child(body)


func _build_collision_faces() -> PackedVector3Array:
	## 按网格分辨率采样地形，展开为三角形汤（与视觉 mesh 同密度）。
	## 先缓存 (segments+1)^2 个顶点高度再连三角形：直接逐顶点调用 _height_at
	## 会有 6 倍冗余（每格 6 顶点但仅 4 个唯一角点），启动耗时大头即在此。
	var n := segments + 1
	var half := size * 0.5
	var cell := size / float(segments)
	var hgrid := PackedFloat32Array()
	hgrid.resize(n * n)
	for iz in n:
		var z := -half + float(iz) * cell
		for ix in n:
			var x := -half + float(ix) * cell
			hgrid[iz * n + ix] = _height_at(x, z)
	# 保留网格供廉价双线性查询（小地图等概览用途；贴物仍须用解析 height_at 保对齐）
	_grid = hgrid
	_grid_n = n
	_grid_half = half
	_grid_cell = cell

	var pts := PackedVector3Array()
	pts.resize(segments * segments * 6)
	var w := 0
	for iz in segments:
		var z0 := -half + float(iz) * cell
		var z1 := z0 + cell
		for ix in segments:
			var x0 := -half + float(ix) * cell
			var x1 := x0 + cell
			var h00: float = hgrid[iz * n + ix]
			var h10: float = hgrid[iz * n + ix + 1]
			var h01: float = hgrid[(iz + 1) * n + ix]
			var h11: float = hgrid[(iz + 1) * n + ix + 1]
			pts[w] = Vector3(x0, h00, z0); w += 1
			pts[w] = Vector3(x1, h10, z0); w += 1
			pts[w] = Vector3(x0, h01, z1); w += 1
			pts[w] = Vector3(x1, h10, z0); w += 1
			pts[w] = Vector3(x1, h11, z1); w += 1
			pts[w] = Vector3(x0, h01, z1); w += 1
	return pts


func _build_boundary_walls() -> void:
	## 地形四周边界墙，防止走出地形范围掉落（地形起伏 ±12，墙须埋深加高防跳过）
	var half := size * 0.5
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall := StaticBody3D.new()
		var ws := BoxShape3D.new()
		var pos := Vector3(0, 1.0, 0)
		if d.x != 0.0:
			ws.size = Vector3(1.0, 30.0, size)
			pos.x = d.x * half
		else:
			ws.size = Vector3(size, 30.0, 1.0)
			pos.z = d.z * half
		var csc := CollisionShape3D.new()
		csc.shape = ws
		wall.add_child(csc)
		wall.position = pos
		add_child(wall)


# ---- 与 shader 同款 fbm 噪声（CPU 端，必须与 ground.gdshader 完全一致） ----
func _hash21(p: Vector2) -> float:
	var q: Vector2 = p * Vector2(123.34, 456.21)
	q = Vector2(q.x - floor(q.x), q.y - floor(q.y))
	var s: float = q.dot(q + Vector2(45.32, 45.32))
	q = q + Vector2(s, s)
	var r: float = q.x * q.y
	return r - floor(r)


func _vnoise(p: Vector2) -> float:
	var ix: float = floor(p.x)
	var iy: float = floor(p.y)
	var fx: float = p.x - ix
	var fy: float = p.y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _hash21(Vector2(ix, iy))
	var b: float = _hash21(Vector2(ix + 1.0, iy))
	var c: float = _hash21(Vector2(ix, iy + 1.0))
	var d: float = _hash21(Vector2(ix + 1.0, iy + 1.0))
	return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy


func _fbm(p: Vector2) -> float:
	var v: float = 0.0
	var amp: float = 0.5
	for k in 5:
		v += amp * _vnoise(p)
		var qx: float = (p.x * 0.8 + p.y * 0.6) * 2.02
		p.y = (-0.6 * p.x + 0.8 * p.y) * 2.02
		p.x = qx
		amp *= 0.5
	return v
