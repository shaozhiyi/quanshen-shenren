extends Node3D
## 程序化起伏地形：fbm 高度场；碰撞用三角网格（ConcavePolygonShape3D）贴合地形。
## 物理体必须在物理帧之后创建，场景加载期创建的碰撞体不会被物理世界接收。
## 随机生成：randomize_terrain=true 时每局的山脊走向、疏密、起伏幅度都由 terrain_seed
## 决定（-1 = 每次启动随机；填固定种子可复现同一片地形）。CPU 与 shader 共用同一组
## 噪声偏移，务必保持两侧公式一致，否则视觉、碰撞、贴物会错位。

@export var size := 500.0
@export var segments := 128
@export var height_amp := 13.0
@export var frequency := 0.009
@export var randomize_terrain := true    # false = 永远用上面导出的固定参数（原始那张图）
@export var seed_value := -1             # -1 = 每次启动随机；>=0 = 固定种子
@export var amp_range := Vector2(13.0, 17.0)        # 随机起伏幅度区间（偏好明显大起伏，不给平原）
@export var freq_range := Vector2(0.0085, 0.0115)   # 随机山体疏密区间（偏密一点，山丘更频繁）

const GROUND_SHADER := preload("res://shaders/ground.gdshader")
const CHUNK_ROWS := 6               # 分片行数：129 行 ≈ 22 片，每片约 80 毫秒，动画才有得动

var terrain_seed := 0                    # 本局实际生效的种子
var noise_off0 := Vector2.ZERO           # 三层 fbm 的域偏移（与 shader 同名 uniform 一致）
var noise_off2 := Vector2(17.0, 3.0)
var noise_off3 := Vector2(7.0, 11.0)

# 碰撞构建时缓存的高度网格（供 height_at_fast）
var _grid: PackedFloat32Array
var _grid_n := 0
var _grid_half := 0.0
var _grid_cell := 1.0


func _ready() -> void:
	add_to_group("ground")
	_resolve_seed()
	# mesh 立即生成（渲染需要）；物理体延迟到第一个物理帧创建
	LoadingUI.stage(0.38, "正在铺地表材质…")
	_build_terrain_mesh()
	await get_tree().physics_frame
	# 加载界面盖着 → 按行切片建碰撞（每片让出一帧，动画才动得起来）；
	# 没有加载层（直接进场景 / 无头自检）→ 仍一口建完，保持"两帧后就能用"的老约定
	if LoadingUI.active():
		await _build_collision_chunked()
	else:
		_build_collision()
	_build_boundary_walls()
	LoadingUI.stage(0.98, "世界就绪")
	LoadingUI.finish()


func _resolve_seed() -> void:
	## 定种子 → 定噪声偏移/幅度/频率；同时把全局 RNG 绑到该种子，
	## 让 BOSS 落点、技能随机游走、石子散布都能靠同一颗种子复现
	## 优先级：菜单指定的 pending_seed（新游戏选种子 / 读档）> 导出的 seed_value > 每次随机
	if SaveManager.pending_seed >= 0:
		terrain_seed = SaveManager.pending_seed
	elif seed_value >= 0:
		terrain_seed = seed_value
	else:
		terrain_seed = int(Time.get_unix_time_from_system()) ^ (randi() << 8)
	seed(terrain_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed
	if randomize_terrain:
		# 偏移控制在 0~26：与原固定偏移同量级，避免 float32 精度损失
		noise_off0 = Vector2(rng.randf_range(0.0, 26.0), rng.randf_range(0.0, 26.0))
		noise_off2 = Vector2(rng.randf_range(0.0, 26.0), rng.randf_range(0.0, 26.0))
		noise_off3 = Vector2(rng.randf_range(0.0, 26.0), rng.randf_range(0.0, 26.0))
		height_amp = rng.randf_range(amp_range.x, amp_range.y)
		frequency = rng.randf_range(freq_range.x, freq_range.y)
		# 读档时直接沿用存档里记下的地形参数，保证山形与当初完全一致
		var saved: Dictionary = SaveManager.pending_load
		if saved.has("amp") and saved.has("freq"):
			height_amp = float(saved.get("amp", height_amp))
			frequency = float(saved.get("freq", frequency))
	print("[terrain] 地形种子=%d 起伏幅度=%.2f 频率=%.5f 随机=%s" % [
		terrain_seed, height_amp, frequency, randomize_terrain])


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


func grid_ready() -> bool:
	## 高度网格（= 地面 mesh 的顶点表）是否已经建好，surface_height 才有准头
	return _grid_n > 1 and _grid.size() == _grid_n * _grid_n


func surface_height(x: float, z: float) -> float:
	## 贴物专用：返回地面 mesh **真正铺出来**的那个高度，不是解析式高度。
	## height_at 带 5 层倍频，最高频那几层在 3.9 米一格的顶点网格上根本没采到，
	## 于是渲染出来的地面是被抹平的版本，两者实测平均差 0.13 米、最大差 0.85 米
	## ——石子按解析高度摆就整片悬空。这里按 _fill_grid_tris 的同一条副对角线
	## 在网格里做三角线性插值，与视觉面/碰撞面严格同一张皮。
	if not grid_ready():
		return _height_at(x, z)
	var fx := clampf((x + _grid_half) / _grid_cell, 0.0, float(_grid_n - 1) - 0.001)
	var fz := clampf((z + _grid_half) / _grid_cell, 0.0, float(_grid_n - 1) - 0.001)
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
	if tx + tz <= 1.0:
		# 三角形 A(x0,z0)-B(x1,z0)-C(x0,z1)
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	# 三角形 B(x1,z0)-D(x1,z1)-C(x0,z1)
	var u := tx + tz - 1.0
	var v := 1.0 - tx
	return h10 + (h11 - h10) * u + (h01 - h10) * v


func normal_at(x: float, z: float) -> Vector3:
	## 地表法线（中心差分，与 shader 顶点法线同公式），供草/杂物沿坡倾斜
	var e := 0.5
	var h := _height_at(x, z)
	var hx := _height_at(x + e, z)
	var hz := _height_at(x, z + e)
	return Vector3(h - hx, e, h - hz).normalized()


func _height_at(x: float, z: float) -> float:
	## 与 ground.gdshader 的 terrain_height() 同式（含随机域偏移），改动必须两侧同步
	var p := Vector2(x, z) * frequency
	var n := _fbm(p + noise_off0)
	var n2 := _fbm(p * 4.0 + noise_off2)
	var n3 := _fbm(p * 6.0 + noise_off3)
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
	mat.set_shader_parameter("noise_off0", noise_off0)
	mat.set_shader_parameter("noise_off2", noise_off2)
	mat.set_shader_parameter("noise_off3", noise_off3)
	mat.set_shader_parameter("height_step", size / float(segments))
	mat.set_shader_parameter("albedo_tex", load("res://assets/ground/leafy_grass_diff_2k.jpg"))
	mat.set_shader_parameter("normal_tex", load("res://assets/ground/leafy_grass_nor_gl_2k.jpg"))
	mat.set_shader_parameter("rough_tex", load("res://assets/ground/leafy_grass_rough_2k.jpg"))
	plane.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = plane
	add_child(mi)


func _build_collision() -> void:
	## 一口建完（无加载层时用）：与分片版走同一套逐行函数，结果完全一致
	var n := segments + 1
	var half := size * 0.5
	var cell := size / float(segments)
	var hgrid := _sample_grid(n, half, cell)
	_cache_grid(hgrid, n, half, cell)
	_attach_collision_body(_build_collision_faces(hgrid, n, half, cell))


func _build_collision_chunked() -> void:
	## 分片版（加载界面盖着时用）：高度场是启动耗时大头（约 1.5~1.9 秒），
	## 按行切片、每片之间 await 一帧，让 LoadingUI 真的能画出新帧。
	var n := segments + 1
	var half := size * 0.5
	var cell := size / float(segments)
	var t0 := Time.get_ticks_msec()
	var hgrid := PackedFloat32Array()
	hgrid.resize(n * n)
	for iz in n:
		_sample_grid_row(hgrid, n, half, cell, iz)
		if (iz + 1) % CHUNK_ROWS == 0 or iz == n - 1:
			LoadingUI.stage(0.40 + 0.40 * float(iz + 1) / float(n), "正在生成地形起伏…")
			await get_tree().physics_frame
	_cache_grid(hgrid, n, half, cell)
	var t1 := Time.get_ticks_msec()
	var pts := PackedVector3Array()
	pts.resize(segments * segments * 6)
	var w := 0
	for iz in segments:
		w = _fill_grid_tris(pts, w, hgrid, n, half, cell, iz)
		if (iz + 1) % CHUNK_ROWS == 0 or iz == segments - 1:
			LoadingUI.stage(0.80 + 0.14 * float(iz + 1) / float(segments), "正在铺设碰撞面…")
			await get_tree().physics_frame
	print("[terrain] 碰撞构建：高度场 %d ms + 三角面 %d ms" % [t1 - t0, Time.get_ticks_msec() - t1])
	_attach_collision_body(pts)


func _sample_grid(n: int, half: float, cell: float) -> PackedFloat32Array:
	var hgrid := PackedFloat32Array()
	hgrid.resize(n * n)
	for iz in n:
		_sample_grid_row(hgrid, n, half, cell, iz)
	return hgrid


func _sample_grid_row(hgrid: PackedFloat32Array, n: int, half: float, cell: float, iz: int) -> void:
	## 一行高度（与 ground.gdshader 同式，逐点解析采样，保证视觉/碰撞/贴物对齐）
	var z := -half + float(iz) * cell
	for ix in n:
		var x := -half + float(ix) * cell
		hgrid[iz * n + ix] = _height_at(x, z)


func _cache_grid(hgrid: PackedFloat32Array, n: int, half: float, cell: float) -> void:
	## 保留网格供廉价查询：height_at_fast 双线性（小地图等概览）、
	## surface_height 三角插值（贴石子/放 BOSS，与视觉面严格同一张皮）
	_grid = hgrid
	_grid_n = n
	_grid_half = half
	_grid_cell = cell


func _build_collision_faces(hgrid: PackedFloat32Array, n: int, half: float, cell: float) -> PackedVector3Array:
	## 把高度网格展开为三角形汤（与视觉 mesh 同密度）
	var pts := PackedVector3Array()
	pts.resize(segments * segments * 6)
	var w := 0
	for iz in segments:
		w = _fill_grid_tris(pts, w, hgrid, n, half, cell, iz)
	return pts


func _fill_grid_tris(pts: PackedVector3Array, w: int, hgrid: PackedFloat32Array,
		n: int, half: float, cell: float, iz: int) -> int:
	## 第 iz 行格子 → 6 个顶点（两个三角形），返回下一个写入位置
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
	return w


func _attach_collision_body(pts: PackedVector3Array) -> void:
	## 三角网格物理体：必须在物理帧之后创建，场景加载期创建的碰撞体不会被物理世界接收
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(pts)
	var body := StaticBody3D.new()
	var csc := CollisionShape3D.new()
	csc.shape = shape
	body.add_child(csc)
	add_child(body)


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
