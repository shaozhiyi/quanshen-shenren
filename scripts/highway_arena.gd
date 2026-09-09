extends Node3D
## 国道战斗空间：两条无限延伸的国道（大运专属 BOSS 空间）。
##
## 与纯白空间（arena.gd）并列，对外 API 完全一致：
##   ARENA_CENTER / center() / floor_y() / inside() / set_active() / is_active() /
##   bounds_half() / theme_key() / arena_env / set_day_night()
## 玩家按 E 进哪套空间由名册字段 arena 决定（大运 = "highway"，其余 = "white"）。
##
## "无限延伸"怎么做到（全部程序化，不依赖外部模型）：
##   1) 路面与田野是 800 米的大面片，配浓雾（能见度约 200 米）根本看不到尽头；
##   2) 车道虚线 = 一整条面片 + 纵向平铺贴图，一条就画满全路，不用几百个对象；
##   3) 护栏桩 / 灯杆 / 电线杆用 MultiMesh，每类只占一次 draw call；
##   4) 真正的"无限"来自池化路灯：4 盏 OmniLight 每帧吸附到离玩家最近的几盏灯头，
##      跑到哪灯都在头顶前后亮着，永远数不完。
## 只有地面那块厚盒参与碰撞（隔离带、护栏、灯杆、龙门架都是纯视觉），
## 免得战斗时玩家或大运被路沿卡住。
const ARENA_CENTER := Vector3(0.0, 100.0, -3000.0)
const FLOOR_SIZE := 800.0
const HALF := FLOOR_SIZE / 2.0
# ---- 道路横断面（相对空间中心的 x，米）----
const MEDIAN_HALF := 3.5        # 中央分隔带半宽
const LANE_OUT := 15.5          # 单向车行道外缘
const SHOULDER_OUT := 19.0      # 路肩外缘
const POST_STEP := 6.0          # 护栏桩间距
const LAMP_STEP := 32.0         # 路灯间距
const POLE_STEP := 48.0         # 远处电线杆间距
const LANE_RIGHT := 12.5        # 右侧行车道中心（靠右行驶，不压车道虚线）
const LAMP_POOL := 4            # 池化光源数量
# ---- 「无法离开国道」：能把人夹住的横向范围（相对中心 x，米）----
# 左边界 = 中央隔离带护栏内侧，右边界 = 路肩护栏内侧；各留余量免得人物贴进护栏
const WALK_MIN_X := MEDIAN_HALF + 0.7      # 4.2
const WALK_MAX_X := SHOULDER_OUT - 0.6     # 18.4
var arena_env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _sky_mat: ProceduralSkyMaterial
var _lamp_mat: StandardMaterial3D
var _lamps: Array[OmniLight3D] = []
var _lamp_heads: PackedVector3Array = PackedVector3Array()
var _night := 0.0
# 黄昏基调
const DUSK_TOP := Color(0.10, 0.13, 0.30)
const DUSK_HORIZON := Color(0.92, 0.52, 0.26)
const NIGHT_TOP := Color(0.02, 0.03, 0.09)
const NIGHT_HORIZON := Color(0.10, 0.12, 0.26)
const ASPHALT := Color(0.16, 0.16, 0.18)
const SHOULDER_COL := Color(0.235, 0.225, 0.215)
const FIELD_COL := Color(0.155, 0.19, 0.135)
const CURB_COL := Color(0.42, 0.42, 0.44)
const LAMP_COL := Color(1.0, 0.86, 0.58)
func _ready() -> void:
	add_to_group("arena")
	position = ARENA_CENTER
	visible = false
	_build_env()
	_build_lights()
	_build_ground()
	_build_roads()
	_build_median()
	_build_lamps()
	_build_poles()
	_build_gantries()
# ---- 环境：黄昏天空 + 浓雾（雾是"看不到尽头"的关键）----
func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = DUSK_TOP
	psm.sky_horizon_color = DUSK_HORIZON
	psm.ground_bottom_color = Color(0.07, 0.08, 0.10)
	psm.ground_horizon_color = DUSK_HORIZON
	psm.sun_angle_max = 12.0
	psm.sun_curve = 0.25
	sky.sky_material = psm
	env.sky = sky
	_sky_mat = psm
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = DUSK_HORIZON.lerp(Color(0.5, 0.5, 0.58), 0.4)
	env.fog_light_energy = 0.5
	env.fog_density = 0.0068          # 约 200 米外基本全化掉，看不见路尾
	env.fog_height = 100.0
	env.fog_height_density = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.06
	arena_env = env
func _build_lights() -> void:
	# 低角度暖色夕阳（拉出长影）+ 冷色补光（背光面不糊成黑）
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-12.0, 118.0, 0.0)
	_sun.light_color = Color(1.0, 0.72, 0.45)
	_sun.light_energy = 1.15
	_sun.shadow_enabled = true
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-42.0, -60.0, 0.0)
	_fill.light_color = Color(0.62, 0.72, 1.0)
	_fill.light_energy = 0.32
	_fill.shadow_enabled = false
	add_child(_fill)
# ---- 地面：整块田野 + 一块参与碰撞的厚盒 ----
func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	pm.material = _base_mat(FIELD_COL)
	mi.mesh = pm
	add_child(mi)
	add_child(_slab(Vector3(0, -0.5, 0), Vector3(FLOOR_SIZE, 1.0, FLOOR_SIZE)))
# ---- 路面：两条车行道 + 路肩 + 四类标线 ----
func _build_roads() -> void:
	var asp := _asphalt_mat()
	for side in [-1.0, 1.0]:
		var mid: float = side * (MEDIAN_HALF + LANE_OUT) * 0.5   # 车行道中心 ±9.5
		_strip(mid, LANE_OUT - MEDIAN_HALF, 0.03, asp)          # 12 米宽车行道
		_strip(side * (LANE_OUT + SHOULDER_OUT) * 0.5, SHOULDER_OUT - LANE_OUT, 0.025,
			_base_mat(SHOULDER_COL))                            # 路肩
		_strip(side * (LANE_OUT - 0.35), 0.18, 0.05, _flat_mat(Color(0.93, 0.93, 0.91)))
		_strip(side * (MEDIAN_HALF + 0.35), 0.18, 0.05, _flat_mat(Color(0.96, 0.78, 0.15)))
		_strip(mid, 0.16, 0.05, _dash_mat(Color(0.94, 0.94, 0.92)))   # 同向车道分界虚线
# ---- 中央分隔带：水泥带 + 两侧波形护栏（纯视觉，不挡人）----
func _build_median() -> void:
	var curb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(MEDIAN_HALF * 2.0 - 0.6, 0.30, FLOOR_SIZE)
	curb.mesh = bm
	curb.position = Vector3(0, 0.15, 0)
	curb.material_override = _base_mat(CURB_COL)
	add_child(curb)
	var posts: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		var x: float = side * (MEDIAN_HALF - 0.35)
		var beam := MeshInstance3D.new()
		var qb := BoxMesh.new()
		qb.size = Vector3(0.16, 0.30, FLOOR_SIZE)
		beam.mesh = qb
		beam.position = Vector3(x, 0.72, 0)
		beam.material_override = _metal_mat(Color(0.72, 0.74, 0.78))
		add_child(beam)
		var z := -HALF + 3.0
		while z < HALF - 3.0:
			posts.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.45, z)))
			z += POST_STEP
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.90, 0.12)
	add_child(_multimesh(post, posts, _metal_mat(Color(0.55, 0.57, 0.60))))
# ---- 路灯：灯杆 + 发光灯头（MultiMesh）+ 池化 OmniLight 跟着玩家走 ----
func _build_lamps() -> void:
	var pole_mats: Array[Transform3D] = []
	var head_mats: Array[Transform3D] = []
	var idx := 0
	var z := -HALF + 8.0
	while z < HALF - 8.0:
		var side := 1.0 if idx % 2 == 0 else -1.0
		var x: float = side * (SHOULDER_OUT + 0.9)
		pole_mats.append(Transform3D(Basis.IDENTITY, Vector3(x, 4.0, z)))
		# 灯头：长轴沿 x（横跨路面），从杆子伸到外侧车道上方
		var hx := x - side * 1.9
		head_mats.append(Transform3D(Basis.IDENTITY, Vector3(hx, 7.8, z)))
		_lamp_heads.append(ARENA_CENTER + Vector3(hx, 7.6, z))
		z += LAMP_STEP
		idx += 1
	var pole := CylinderMesh.new()
	pole.top_radius = 0.10
	pole.bottom_radius = 0.16
	pole.height = 8.0
	add_child(_multimesh(pole, pole_mats, _metal_mat(Color(0.34, 0.36, 0.39))))
	var head := BoxMesh.new()
	head.size = Vector3(1.2, 0.16, 0.34)
	_lamp_mat = _base_mat(LAMP_COL, 2.8)
	add_child(_multimesh(head, head_mats, _lamp_mat))
	for i in LAMP_POOL:
		var om := OmniLight3D.new()
		om.light_color = Color(1.0, 0.78, 0.46)
		om.light_energy = 1.2
		om.omni_range = 14.0
		om.omni_attenuation = 1.4
		om.shadow_enabled = false
		add_child(om)
		_lamps.append(om)
# ---- 远处电线杆：给"路还在往前伸"一个更远的参照 ----
func _build_poles() -> void:
	var mats: Array[Transform3D] = []
	var z := -HALF + 20.0
	var idx := 0
	while z < HALF - 20.0:
		var x: float = (1.0 if idx % 2 == 0 else -1.0) * (SHOULDER_OUT + 14.0)
		mats.append(Transform3D(Basis.IDENTITY, Vector3(x, 4.5, z)))
		z += POLE_STEP
		idx += 1
	var pole := CylinderMesh.new()
	pole.top_radius = 0.13
	pole.bottom_radius = 0.22
	pole.height = 9.0
	add_child(_multimesh(pole, mats, _base_mat(Color(0.30, 0.27, 0.24))))
# ---- 龙门架路牌：蓝底白字「国道 G108」----
func _build_gantries() -> void:
	var sign_tex: Texture2D = null
	if ResourceLoader.exists("res://assets/props/road/g108_sign.png"):
		sign_tex = load("res://assets/props/road/g108_sign.png") as Texture2D
	var frame := _metal_mat(Color(0.36, 0.38, 0.41))
	for gz in [-180.0, 0.0, 180.0]:
		var g := Node3D.new()
		g.position = Vector3(0, 0, gz)
		var post_x := SHOULDER_OUT + 0.6
		for side in [-1.0, 1.0]:
			var col := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.34, 8.6, 0.34)
			col.mesh = cm
			col.position = Vector3(side * post_x, 4.3, 0)
			col.material_override = frame
			g.add_child(col)
		var beam := MeshInstance3D.new()
		var bmx := BoxMesh.new()
		bmx.size = Vector3(post_x * 2.0, 0.42, 0.42)
		beam.mesh = bmx
		beam.position = Vector3(0, 8.3, 0)
		beam.material_override = frame
		g.add_child(beam)
		if sign_tex != null:
			for side in [-1.0, 1.0]:
				var sm := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(6.4, 1.8)
				sm.mesh = q
				sm.position = Vector3(side * 9.5, 6.8, -0.34)
				sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.albedo_texture = sign_tex
				sm.material_override = m
				g.add_child(sm)
		add_child(g)
# ---- 每帧：把池化灯光挪到离玩家最近的几盏灯头（灯头数组只读，不改）----
func _process(_delta: float) -> void:
	if not visible or _lamps.is_empty() or _lamp_heads.is_empty():
		return
	var p := Vector3.ZERO
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and is_instance_valid(pl):
		p = (pl as Node3D).global_position
	var pairs: Array = []
	for j in _lamp_heads.size():
		pairs.append([p.distance_squared_to(_lamp_heads[j]), j])
	pairs.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var n := mini(_lamps.size(), pairs.size())
	for i in n:
		_lamps[i].global_position = _lamp_heads[int(pairs[i][1])]
## 白天↔深夜（大运目前没有攻击相位，接口先留着；夜里灯更亮）
func set_day_night(night: float) -> void:
	_night = clampf(night, 0.0, 1.0)
	_sun.light_energy = lerpf(1.15, 0.06, _night)
	_fill.light_energy = lerpf(0.32, 0.12, _night)
	_sky_mat.sky_top_color = DUSK_TOP.lerp(NIGHT_TOP, _night)
	_sky_mat.sky_horizon_color = DUSK_HORIZON.lerp(NIGHT_HORIZON, _night)
	_sky_mat.ground_horizon_color = DUSK_HORIZON.lerp(NIGHT_HORIZON, _night)
	arena_env.ambient_light_energy = lerpf(0.9, 0.28, _night)
	arena_env.fog_light_energy = lerpf(0.5, 0.16, _night)
	if _lamp_mat != null:
		_lamp_mat.emission_energy_multiplier = lerpf(2.8, 5.4, _night)
	for om in _lamps:
		om.light_energy = lerpf(1.2, 2.6, _night)
# ---- 小工具 ----
func _strip(x: float, width: float, y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, FLOOR_SIZE)
	pm.material = mat
	mi.mesh = pm
	mi.position = Vector3(x, y, 0)
	add_child(mi)
func _base_mat(col: Color, emission := 0.0) -> StandardMaterial3D:
	## 受光的实体材质（需要自发光时传 emission）
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emission
	return m
func _flat_mat(col: Color) -> StandardMaterial3D:
	## 标线：不受光照影响的纯平色（夜里车灯/路灯下也够醒目）
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
func _metal_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.75
	m.roughness = 0.38
	return m
func _asphalt_mat() -> StandardMaterial3D:
	## 程序化沥青：噪点底 + 平铺，避免一大片纯色
	var m := StandardMaterial3D.new()
	m.albedo_color = ASPHALT
	m.roughness = 0.86
	m.metallic_specular = 0.22
	m.texture_repeat = true
	m.uv1_scale = Vector3(26.0, 26.0, 1.0)
	m.albedo_texture = _noise_tex(128, 20260902)
	return m
func _dash_mat(col: Color) -> StandardMaterial3D:
	## 车道虚线：一整条面片 + 纵向平铺（3 米一段：2 米实线段 + 1 米空）
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_repeat = true
	m.albedo_color = col
	m.uv1_scale = Vector3(1.0, FLOOR_SIZE / 3.0, 1.0)
	m.albedo_texture = _dash_tex()
	return m
static var _dash_cache: ImageTexture
static func _dash_tex() -> ImageTexture:
	if _dash_cache != null:
		return _dash_cache
	var w := 8
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var a := 1.0 if float(y) / float(h) < 0.66 else 0.0
		for x in w:
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_dash_cache = ImageTexture.create_from_image(img)
	return _dash_cache
static var _noise_cache := {}
static func _noise_tex(side: int, seed_val: int) -> ImageTexture:
	var key := "%d_%d" % [side, seed_val]
	if _noise_cache.has(key):
		return _noise_cache[key]
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for y in side:
		for x in side:
			var g := 0.74 + 0.26 * rng.randf()
			if rng.randf() < 0.05:
				g *= 0.84          # 零星暗斑，做出修补/磨损的感觉
			img.set_pixel(x, y, Color(g, g, g * 1.02, 1.0))
	var t := ImageTexture.create_from_image(img)
	_noise_cache[key] = t
	return t
func _multimesh(mesh: Mesh, mats: Array[Transform3D], mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = mats.size()
	for i in mats.size():
		mm.set_instance_transform(i, mats[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if mat != null:
		mi.material_override = mat
	return mi
func _slab(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var csc := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	csc.shape = box
	csc.position = pos
	body.add_child(csc)
	return body
# ---- 对外 API（与 arena.gd 保持一致）----
func theme_key() -> String:
	return "highway"
func center() -> Vector3:
	return ARENA_CENTER
func bounds_half() -> float:
	return HALF
func floor_y() -> float:
	return ARENA_CENTER.y
func set_active(b: bool) -> void:
	visible = b
func is_active() -> bool:
	return visible
## 双方都放在右行的那条车道中心（x=+12.5）：大运顺着国道朝你开过来，
## 而不是压在 9.5 的车道分界虚线上
func player_spawn() -> Vector3:
	return ARENA_CENTER + Vector3(LANE_RIGHT, 1.05, 8.0)
func boss_spawn() -> Vector3:
	return ARENA_CENTER + Vector3(LANE_RIGHT, 0.0, -16.0)
func inside(p: Vector3) -> bool:
	return absf(p.x - ARENA_CENTER.x) < HALF and absf(p.z - ARENA_CENTER.z) < HALF
## 「无法离开国道」：玩家横向被夹在右幅车道内——左边是中央隔离带护栏、右边是路肩护栏，
## 顺着公路跑（z）完全自由。护栏本身仍不做碰撞体，靠这里逐帧夹，免得人物被路沿卡死。
func confine(p: Vector3) -> Vector3:
	var lo := ARENA_CENTER.x + WALK_MIN_X
	var hi := ARENA_CENTER.x + WALK_MAX_X
	var x := clampf(p.x, lo, hi)
	if is_equal_approx(x, p.x):
		return p
	return Vector3(x, p.y, p.z)
