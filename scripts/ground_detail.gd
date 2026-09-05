extends Node3D
## 地表杂物：小石子散布，丰富地表细节，铺满整张地图。
## 关键：石子高度取 terrain.surface_height()（地面 mesh 真正铺出来的那张皮），
## 不是解析式 height_at —— 后者含顶点网格没采到的高频噪声，最多差 0.85 米，
## 用它摆石头会整片悬空。另外要等高度网格建好再摆，否则 surface_height 也退回解析式。
## 布局写成纯函数 rock_layout()：MultiMesh 的实例数据在 GDScript 侧只写不读
## （get_instance_transform 恒返回单位阵），自检只能核对这份布局，顺带也方便调试。

@export var rock_count := 0                  # 0 = 按 rocks_per_1000m2 自动算
@export var rocks_per_1000m2 := 206.0        # 密度：整张 500×500 地图 → 约 5 万颗（每 4.8 ㎡ 一颗）
@export var area_half := 0.0                 # 0 = 铺满整张地图（留一点边距）
@export var edge_margin := 4.0               # 离地形边界/围墙的安全边距（米）
@export var rock_size_w := Vector2(0.20, 0.45)    # 石子宽（米，直径；底模半径 1 米 → 缩放=宽的一半）
@export var rock_size_h := Vector2(0.08, 0.20)    # 石子高（米；底模高 1 米 → 缩放=整高）

const ROCK_SHADER := preload("res://shaders/rock.gdshader")
const SINK := 0.25        # 石头按自身半高往下埋这么多，看起来才"长在地上"


func _ready() -> void:
	if get_child_count() == 0:
		await _build_details()


func _build_details() -> void:
	var ground := _ground()
	if ground != null and ground.has_method("grid_ready"):
		# 高度网格是地形分片建碰撞时才缓存的（可能比我们先，也可能晚很多帧），
		# 等它就绪再摆石头；真等不到就退回解析高度，至少石头不会没有。
		var waited := 0
		while waited < 900 and not bool(ground.call("grid_ready")):
			await get_tree().process_frame
			waited += 1
		if not is_inside_tree():
			return
		if waited > 0:
			print("[ground_detail] 等地形高度网格 %d 帧" % waited)
		if not bool(ground.call("grid_ready")):
			push_warning("ground_detail: 高度网格仍未就绪，石子改用解析高度（可能悬空）")
	var t0 := Time.get_ticks_msec()
	var layout := rock_layout(ground)
	var t1 := Time.get_ticks_msec()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _make_rock_mesh()
	mm.instance_count = layout.size()
	for i in layout.size():
		mm.set_instance_transform(i, layout[i])
		mm.set_instance_custom_data(i, Color(_tint_for(layout[i]), 0.0, 0.0, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	print("[ground_detail] 石子 %d 颗，铺满 %.0f×%.0f 米（算布局 %d ms + 填实例 %d ms）" % [
		layout.size(), _map_half(ground) * 2.0, _map_half(ground) * 2.0,
		t1 - t0, Time.get_ticks_msec() - t1])


# ---- 本局石子布局（纯函数：地形种子 → 每颗石子的变换）----
func rock_layout(ground: Node) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	# 用本局地形种子派生：同一颗种子 → 同一片世界（含石头位置）
	var base: int = int(ground.get("terrain_seed")) if ground != null else 0
	rng.seed = base + 777
	var half := _map_half(ground)
	var out: Array[Transform3D] = []
	for _i in _resolve_count(half):
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var w := rng.randf_range(rock_size_w.x, rock_size_w.y)
		var sy := rng.randf_range(rock_size_h.x, rock_size_h.y)
		var d := rng.randf_range(rock_size_w.x, rock_size_w.y)
		var t := Transform3D.IDENTITY
		# 网格原点在石头中心：按自身半高往下埋，坡面/山脊上也不会露出底缝
		t.origin = Vector3(x, _surface_height(ground, x, z) - sy * 0.5 * SINK, z)
		t.basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(w * 0.5, sy, d * 0.5))
		out.append(t)
	return out


func _resolve_count(half: float) -> int:
	if rock_count > 0:
		return rock_count
	return int((half * 2.0) * (half * 2.0) * rocks_per_1000m2 / 1000.0)


func _map_half(ground: Node) -> float:
	if area_half > 0.0:
		return area_half
	var size: float = float(ground.get("size")) if ground != null else 500.0
	return maxf(size * 0.5 - edge_margin, 10.0)


func _surface_height(ground: Node, x: float, z: float) -> float:
	if ground == null:
		return 0.0
	if ground.has_method("surface_height"):
		return float(ground.call("surface_height", x, z))
	if ground.has_method("height_at"):
		return float(ground.call("height_at", x, z))
	return 0.0


func _ground() -> Node:
	return get_node_or_null("../Ground")


static func _tint_for(t: Transform3D) -> float:
	## 每颗石子的明暗/形变随机数：由位置哈希得到，换种子=换位置=换长相，
	## 不必再占用散布 RNG 的一个序号（shader 里拿它做 INSTANCE_CUSTOM.x）
	var h: float = t.origin.x * 12.9898 + t.origin.z * 78.233
	h = h - floor(h)
	h *= 43758.5453
	return h - floor(h)


func _make_rock_mesh() -> Mesh:
	# 低模石头：细分较少的球体压扁，再叠加 shader 微变形。
	# 段数×环数直接决定总面数：5 段 2 环 = 30 三角，5 万颗 ≈ 150 万三角；
	# 沿用旧的 6 段 4 环（60 三角）就是 300 万三角，MX250 直接跪。
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.0
	sphere.radial_segments = 5
	sphere.rings = 2
	var mat := ShaderMaterial.new()
	mat.shader = ROCK_SHADER
	sphere.material = mat
	return sphere
