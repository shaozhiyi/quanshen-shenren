extends Node3D
## 程序化特效总管（不依赖任何素材，播完自动 queue_free）：
##   spawn_slam()      —— BOSS 砸地：地裂贴图（暗色径向裂纹）+ 一道快速扩散的光环
##   spawn_ring()      —— 轻量单圈（玩家二段跳/冲刺起脚点用）
##   spawn_star()      —— BOSS 射出的立体星点弹（按颜色分红黄蓝绿，各有不同效果与速度）
##   spawn_slash()     —— 挥剑剑气：一道斜月牙弧光，快速放大后淡出
##   spawn_dash_trail()—— 冲刺拖尾：身后数条风痕十字片 + 脚下一圈淡白环
## 贴图用 Image 逐像素画（Godot 的 Image 没有带宽度的画线 API，裂纹用"沿路径盖圆点"实现），
## 生成一次后 static 缓存复用，避免每次砸地都重画 256×256。
## 只做"地裂 + 一圈"两层：纯白场地里加尘圈会在斜视角糊出一大片怪边，反而脏。

const CRACK_SIDE := 256          # 地裂贴图分辨率
const CRACK_LIFE := 2.4          # 地裂残留时长（秒）
const WAVE_LIFE := 0.55          # 扩散光环时长

static var _crack_tex: ImageTexture
static var _ring_tex: ImageTexture
static var _star_tex: ImageTexture
static var _star_mesh: ArrayMesh         # 立体星点（8 面晶簇），全场景共用一份
static var _slash_tex: ImageTexture
static var _streak_tex: ImageTexture

var _t := 0.0
var _radius := 6.0
var _tint := Color(1, 1, 1)
var _want_crack := true
var _wave_life := -1.0
var _crack: MeshInstance3D
var _wave: MeshInstance3D
var _crack_mat: StandardMaterial3D
var _wave_mat: StandardMaterial3D
# 星点弹模式
var _star := false
var _dir := Vector3.DOWN
var _speed := 40.0
var _star_life := 0.9
var _star_size := 1.4
var _vel := Vector3.ZERO
var _star_mi: MeshInstance3D
var _star_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _damage := 5.0                  # 星点单发伤害（0 = 不造成伤害）
var _kind := "yellow"               # 星点颜色规律：red 高伤 / yellow 常规 / blue 减速 / green 回血
var _heal := 0.0                    # 命中给玩家回复的血量（绿色）
var _slow := 0.0                    # 命中给玩家的减速时长（蓝色）
var _base_col := Color(1, 0.93, 0.62)
const STAR_HIT_R := 1.4             # 命中半径（米）
const STAR_GRAVITY := 12.0          # 星点下坠加速度（boss.gd 弹道补偿共用）
const STAR_LIFE_CAP := 8.0          # 兜底自毁上限（正常都应落在地板上消失）
var _hit_done := false
var _prev_pos := Vector3.INF
var _spin := Vector3.ZERO           # 立体星点自转角速度（弧度/秒）
var _glow_mi: MeshInstance3D        # 立体星点外的一圈发光晕（公告板，远处也看得见）
# ---- 剑气 / 冲刺拖尾：由"动画层"列表驱动（每层一片网格，放大 + 淡出）----
var _mode := ""                     # "" = 砸地/光环；slash = 剑气；wind = 冲刺拖尾
var _layers: Array = []             # 每项 {mi, mat, col, a0, a1, s0, s1, delay, life}
var _mode_life := 0.0               # 本模式总时长

# ---- 星点四色：规律固定为红→黄→蓝→绿循环，颜色即效果预告 ----
const STAR_KINDS := ["red", "yellow", "blue", "green"]
const STAR_COLORS := {
	"red": Color(1.0, 0.16, 0.12),
	"yellow": Color(1.0, 0.88, 0.30),
	"blue": Color(0.24, 0.58, 1.0),
	"green": Color(0.26, 0.95, 0.45),
}
# 飞行速度倍率：红色更快更难躲、蓝色更慢好躲（黄色/绿色保持基准）
const STAR_SPEED_MULT := {"red": 1.5, "yellow": 1.0, "blue": 0.7, "green": 1.0}


static func star_kind(index: int) -> String:
	## 第 index 颗环绕星点对应的颜色种类（红黄蓝绿依次循环）
	return STAR_KINDS[posmod(index, STAR_KINDS.size())]


static func star_color(kind: String) -> Color:
	return STAR_COLORS.get(kind, Color(1, 0.93, 0.62))


static func star_speed_mult(kind: String) -> float:
	## 该颜色星点的飞行速度倍率（红 ×1.5、蓝 ×0.7，其余 ×1.0）
	return float(STAR_SPEED_MULT.get(kind, 1.0))


## 砸地特效：at 为地面点（贴地画），radius 为裂纹半径
static func spawn_slam(parent: Node, at: Vector3, radius: float, tint := Color(1, 1, 1)) -> void:
	_spawn(parent, at, radius, tint, true, -1.0)


## 单个扩散光环（二段跳等轻量反馈）
static func spawn_ring(parent: Node, at: Vector3, radius: float, tint := Color(1, 1, 1), life := 0.45) -> void:
	_spawn(parent, at, radius, tint, false, life)


static func _spawn(parent: Node, at: Vector3, radius: float, tint: Color, crack: bool, life: float) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var fx: Node3D = load("res://scripts/slam_fx.gd").new()
	fx._radius = radius
	fx._tint = tint
	fx._want_crack = crack
	fx._wave_life = life
	parent.add_child(fx)
	fx.global_position = at


## 射出的星点：从 at 沿 dir 飞出（带重力），**只有落到地板上才消失**（life 只作兜底上限）
## kind 决定颜色与效果：red 高伤 / yellow 常规 / blue 命中减速 5 秒 / green 无伤但回 5 血
static func spawn_star(parent: Node, at: Vector3, dir: Vector3, speed: float, life: float,
		size: float = 1.4, damage: float = 5.0, kind: String = "yellow") -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var fx: Node3D = load("res://scripts/slam_fx.gd").new()
	fx._star = true
	fx._dir = dir.normalized()
	fx._kind = kind if STAR_COLORS.has(kind) else "yellow"
	# 红色星点更快（更难躲）、蓝色更慢（好躲）；黄/绿保持基准速度
	fx._speed = speed * star_speed_mult(fx._kind)
	fx._star_life = clampf(life, 0.5, STAR_LIFE_CAP)
	fx._star_size = maxf(size, 0.4) * 1.6     # 20 米外要看得见，放大一档
	fx._damage = 0.0 if fx._kind == "green" else damage
	fx._heal = 5.0 if fx._kind == "green" else 0.0
	fx._slow = 5.0 if fx._kind == "blue" else 0.0
	fx._base_col = star_color(fx._kind)
	parent.add_child(fx)
	fx.global_position = at


## 挥剑剑气：在 at 处朝 facing 立一片斜月牙弧光（垂直于视线、跟着挥砍方向放大后淡出）
static func spawn_slash(parent: Node, at: Vector3, facing: Vector3, size := 1.7,
		tint := Color(0.72, 0.86, 1.0)) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var fx: Node3D = load("res://scripts/slam_fx.gd").new()
	fx._mode = "slash"
	fx._tint = tint
	fx._radius = size
	parent.add_child(fx)
	fx.global_position = at
	var to := at + facing
	if facing.length_squared() < 0.0001:
		to = at + Vector3(0.0, 0.0, -1.0)
	fx.look_at(to, Vector3.UP)
	fx._build_slash()


## 冲刺拖尾：从 at 沿 dir 的反方向铺几段风痕（十字片，任何角度都看得见）
static func spawn_dash_trail(parent: Node, at: Vector3, dir: Vector3, length := 3.6,
		tint := Color(0.86, 0.93, 1.0)) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var fx: Node3D = load("res://scripts/slam_fx.gd").new()
	fx._mode = "wind"
	fx._tint = tint
	fx._radius = length
	fx._dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.BACK
	parent.add_child(fx)
	fx.global_position = at
	fx._build_wind()


## 冲刺"眼前"反馈：挂在相机下的一圈径向速度线
## （拖尾留在身后，第一人称根本看不见；要让玩家自己感觉到冲出去，得在视野四周拉风线）
static func spawn_dash_rush(cam: Node3D, tint := Color(0.80, 0.90, 1.0)) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	var fx: Node3D = load("res://scripts/slam_fx.gd").new()
	fx._mode = "rush"
	fx._tint = tint
	cam.add_child(fx)
	fx._build_rush()


static func star_texture() -> ImageTexture:
	## 32×32 四角星：十字星芒 + 亮芯，边缘渐隐（环绕与射出共用一张）
	if _star_tex != null:
		return _star_tex
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := s * 0.5
	for y in s:
		for x in s:
			var dx := (x - c + 0.5) / c
			var dy := (y - c + 0.5) / c
			var v := 0.0
			if absf(dx * dy) < 0.05 and absf(dx) + absf(dy) < 1.0:
				v = 1.0 - (absf(dx) + absf(dy))
			var r := sqrt(dx * dx + dy * dy)
			if r < 0.34:
				v = maxf(v, 1.0 - r * 2.6)
			if v > 0.0:
				img.set_pixel(x, y, Color(1, 0.97, 0.78, clampf(v * 1.35, 0.0, 1.0)))
	_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


func _ready() -> void:
	add_to_group("slam_fx")
	if _star:
		add_to_group("slam_star")
		_vel = _dir * _speed
		var sc := _star_size * 0.9            # star_mesh 高 1 米，这里换算成目标直径
		_star_mi = MeshInstance3D.new()
		_star_mi.mesh = star_mesh()
		_star_mi.scale = Vector3.ONE * sc
		_star_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true    # 逐面明暗写进顶点色，棱面才看得出转折
		mat.albedo_color = _base_col
		mat.metallic = 0.2
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = _base_col
		mat.emission_energy_multiplier = 1.6
		_star_mi.material_override = mat
		_star_mat = mat
		add_child(_star_mi)
		# 外围光晕：公告板四角星，远处也能锁定它在哪
		_glow_mi = MeshInstance3D.new()
		var gm := QuadMesh.new()
		gm.size = Vector2(sc * 1.5, sc * 1.5)
		_glow_mi.mesh = gm
		_glow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var gmat := StandardMaterial3D.new()
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		gmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		gmat.albedo_texture = star_texture()
		gmat.albedo_color = Color(_base_col.r, _base_col.g, _base_col.b, 0.75)
		_glow_mi.material_override = gmat
		_glow_mat = gmat                      # _process 里用它做脉动闪烁
		add_child(_glow_mi)
		_spin = Vector3(randf_range(2.0, 4.5), randf_range(4.0, 7.0), randf_range(1.0, 2.5))
		return
	if _mode != "":
		return        # 剑气 / 冲刺拖尾：网格由 _build_slash()、_build_wind() 在摆好朝向后建
	# 地裂：贴地的方形面片（暗色裂纹，抬 0.02 防与地面穿模）
	if _want_crack:
		_crack = _make_quad(crack_texture(), _radius * 2.0, 0.02)
		_crack_mat = _crack.material_override as StandardMaterial3D
		_crack.scale = Vector3(0.55, 1.0, 0.55)
	# 扩散光环：从中心快速推出去
	_wave = _make_quad(ring_texture(), _radius * 2.6, 0.05)
	_wave_mat = _wave.material_override as StandardMaterial3D
	_wave.scale = Vector3(0.12, 1.0, 0.12)


func _try_hit_player(from: Vector3, to: Vector3) -> void:
	## 用"本帧起点→终点"这条线段到玩家身体中心的最近距离判命中：
	## 星点 42 米/秒、每帧位移约 0.7 米，直接点距判会在低帧率下穿过去
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not is_instance_valid(p):
		return
	var center: Vector3 = p.global_position + Vector3(0.0, 0.9, 0.0)
	if _seg_point_dist(from, to, center) > STAR_HIT_R:
		return
	_hit_done = true
	if _damage > 0.0 and p.has_method("take_damage"):
		p.take_damage(_damage)          # 吃防具减伤与无敌免疫
	if _slow > 0.0 and p.has_method("apply_slow"):
		p.apply_slow(_slow)             # 蓝色：移速 -50% 持续 5 秒（无敌期免疫）
	if _heal > 0.0 and p.has_method("heal"):
		p.heal(_heal)                   # 绿色：不回血上限外，直接 +5


func _floor_y(p: Vector3) -> float:
	## 星点下方最近的地面：地形表面；若它还在 BOSS 空间地板上方，则空间地板更优先
	## （空间边框 800 米，大地图坐标几乎全落在里面，不能无条件取地板，
	##  否则地形上方飞的星点会被 100 米高的空间地板当场拦下）
	var y := -1000.0
	var ground := get_tree().get_first_node_in_group("ground")
	if ground != null and ground.has_method("height_at"):
		y = float(ground.call("height_at", p.x, p.z))
	var arena := get_tree().get_first_node_in_group("arena")
	if arena != null and arena.has_method("inside") and bool(arena.call("inside", p)):
		var af := float(arena.call("floor_y"))
		if p.y >= af - 0.5:
			y = maxf(y, af)
	return y


func _land_puff() -> void:
	## 落点反馈：一圈本颜色的小光环（绿色落地上也该看得出来是"补血"的那颗）
	var p := get_parent()
	if p == null or not is_instance_valid(p):
		return
	var gy := _floor_y(global_position)
	spawn_ring(p, Vector3(global_position.x, gy + 0.05, global_position.z), 1.1, _base_col, 0.34)


static func _seg_point_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


func _make_quad(tex: Texture2D, size: float, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	# PlaneMesh 天生就是 XZ 水平面（法线 +Y），无需再旋转
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 否则透明区也会投出整块方影
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	mat.albedo_color = _tint
	mi.material_override = mat
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	if _star:
		var from := global_position
		_vel.y -= STAR_GRAVITY * delta
		global_position += _vel * delta
		if _star_mi != null and _spin.length_squared() > 0.0001:
			_star_mi.rotate_object_local(_spin.normalized(), _spin.length() * delta)
		if _glow_mat != null:
			var pulse := 0.62 + 0.28 * sin(_t * 12.0)
			_glow_mat.albedo_color = Color(_base_col.r, _base_col.g, _base_col.b, pulse)
		if not _hit_done:
			_try_hit_player(from, global_position)
			if _hit_done:
				queue_free()      # 命中即炸掉，不重复结算
				return
		# 关键修正：星点不再"飞到一半自己消失"，只有落到地板才消失
		# （旧版按 0.9 秒生命自毁，离玩家远时根本飞不到就没了）
		if global_position.y <= _floor_y(global_position) + 0.06 or _t >= _star_life:
			_land_puff()
			queue_free()
		return
	if _mode != "":
		var all_done := true
		for L in _layers:
			var w := clampf((_t - float(L["delay"])) / float(L["life"]), 0.0, 1.0)
			if w < 1.0:
				all_done = false
			var e := 1.0 - (1.0 - w) * (1.0 - w)      # 出手快、末尾缓
			var mi: MeshInstance3D = L["mi"]
			var mt: StandardMaterial3D = L["mat"]
			if mi != null:
				var s := lerpf(float(L["s0"]), float(L["s1"]), e)
				mi.scale = Vector3(s, s, s)
			if mt != null:
				var col: Color = L["col"]
				mt.albedo_color = Color(col.r, col.g, col.b,
					lerpf(float(L["a0"]), float(L["a1"]), w))
		if all_done or _t >= _mode_life:
			queue_free()
		return
	var wl := WAVE_LIFE if _wave_life < 0.0 else _wave_life
	if _crack != null and _crack_mat != null:
		# 前 0.22 秒绽开到满尺寸，之后慢慢淡出（留下"地裂过"的痕迹）
		var s := lerpf(0.55, 1.0, clampf(_t / 0.22, 0.0, 1.0))
		_crack.scale = Vector3(s, 1.0, s)
		var fade := 1.0 if _t < 0.7 else clampf(1.0 - (_t - 0.7) / (CRACK_LIFE - 0.7), 0.0, 1.0)
		_crack_mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, fade)
	if _wave != null and _wave_mat != null:
		var w := clampf(_t / wl, 0.0, 1.0)
		var ws := lerpf(0.12, 1.0, 1.0 - (1.0 - w) * (1.0 - w))   # 出手快、末尾缓
		_wave.scale = Vector3(ws, 1.0, ws)
		_wave_mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, (1.0 - w) * 0.95)
	if _t >= maxf(CRACK_LIFE if _want_crack else 0.0, wl):
		queue_free()


# ---- 剑气：一道细长弧光 + 一层放大淡晕（叠加发光），沿挥砍方向快速放大后淡出 ----
func _build_slash() -> void:
	var size := maxf(_radius, 0.6)
	_mode_life = 0.30
	# 弧面立在局部 XY 平面（节点已 look_at 让 -Z 指向挥砍方向 → 面正对玩家）
	_add_layer_quad(slash_texture(), Vector3(0.0, 0.0, -0.40),
		Vector3(0.0, 0.0, -40.0), Vector2(size, size), _tint, 0.84, 1.0, 0.95, 0.0, 0.0, 0.30, true)
	_add_layer_quad(slash_texture(), Vector3(0.0, 0.0, -0.37),
		Vector3(0.0, 0.0, -40.0), Vector2(size * 0.92, size * 0.92),
		Color(0.85, 0.93, 1.0), 0.90, 1.02, 0.30, 0.0, 0.03, 0.28, true)


# ---- 冲刺拖尾：沿运动反方向铺 4 段风痕十字片 + 身前一圈淡白环 ----
func _build_wind() -> void:
	var length := maxf(_radius, 1.2)
	_mode_life = 0.42
	var side := _dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	for i in 4:
		var back := 0.35 + length * (0.18 + 0.24 * float(i))
		var up := 0.45 + 0.42 * float(i % 3)
		var drift := side * (randf_range(-0.42, 0.42))
		var at := -_dir * back + Vector3.UP * up + drift
		# 十字：同一段风痕铺两片互相垂直的，任何视角都不会压成一条线
		var yaw := rad_to_deg(atan2(-_dir.x, -_dir.z))
		for k in 2:
			_add_layer_quad(streak_texture(), at,
				Vector3(0.0, yaw + 90.0 * float(k), 0.0),
				Vector2(length * 0.46, 0.42), _tint, 0.5, 1.25, 0.95, 0.0, 0.02 * i, 0.36, true)
	var p := get_parent()
	if p != null and is_instance_valid(p):
		spawn_ring(p, global_position + Vector3(0.0, 0.06, 0.0), 1.35, Color(1, 1, 1), 0.34)


# ---- 冲刺速度线：挂在相机下，绕视野一圈 9 条径向风痕向外拉伸淡出 ----
func _build_rush() -> void:
	_mode_life = 0.26
	position = Vector3.ZERO          # 跟着相机走（本节点就是相机的子节点）
	for i in 9:
		var ang := TAU * float(i) / 9.0 + randf_range(-0.12, 0.12)
		# 半径推大到视野边缘：中间（准星与目标）保持干净，只在四周拉风线
		var rad := 0.62 + randf_range(-0.05, 0.07)
		var at := Vector3(cos(ang) * rad, sin(ang) * rad * 0.86, -0.55)
		_add_layer_quad(streak_texture(), at,
			Vector3(0.0, 0.0, rad_to_deg(ang)), Vector2(0.34, 0.05),
			_tint, 0.80, 1.55, 0.62, 0.0, randf_range(0.0, 0.03), 0.22, true)


## 建一片受 _layers 统一驱动的 quad（位置/欧拉角/尺寸/颜色/起止缩放与透明度/延迟时长）
## add=true 用叠加混合：亮背景上也不会糊成一团灰雾，而是发光
func _add_layer_quad(tex: Texture2D, pos: Vector3, rot_deg: Vector3, size: Vector2,
		col: Color, s0: float, s1: float, a0: float, a1: float, delay: float, life: float,
		add := false) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if add:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = tex
	mat.albedo_color = Color(col.r, col.g, col.b, a0)
	mi.material_override = mat
	add_child(mi)
	_layers.append({"mi": mi, "mat": mat, "col": col, "a0": a0, "a1": a1,
		"s0": s0, "s1": s1, "delay": delay, "life": maxf(life, 0.05)})


# ---- 共用资源：立体星点晶簇（8 面，高 1 米、宽 0.44 米，逐面明暗不同）----
static func star_mesh() -> ArrayMesh:
	if _star_mesh != null:
		return _star_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ty := 0.5           # 上下尖（整颗星高 1 米）
	var tx := 0.22          # 四个侧尖
	var top := Vector3(0, ty, 0)
	var bot := Vector3(0, -ty, 0)
	var pts := [Vector3(tx, 0, 0), Vector3(0, 0, tx), Vector3(-tx, 0, 0), Vector3(0, 0, -tx)]
	for i in 4:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % 4]
		# 相邻两尖之间再放一对更短的腰点，轮廓才像"星"而不是"菱形"
		var mid := (a + b).normalized() * tx * 0.42
		_tri(st, top, a, mid, 1.0 - 0.16 * float(i))
		_tri(st, top, mid, b, 0.94 - 0.16 * float(i))
		_tri(st, bot, mid, a, 0.62 - 0.12 * float(i))
		_tri(st, bot, b, mid, 0.56 - 0.12 * float(i))
	_star_mesh = st.commit()
	return _star_mesh


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, bright: float) -> void:
	## 加一个三角面：法线朝外（朝内就换序）、整面同一个亮度（顶点色 → 棱面看得见）
	var cen := (a + b + c) * (1.0 / 3.0)
	var n := (b - a).cross(c - a).normalized()
	if n.dot(cen) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	var col := Color(bright, bright, bright, 1.0)
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


# ---- 剑气：细长弧形刀光（半径 0.78→1.0 的窄带，张角约 195°，两端渐隐）----
static func slash_texture() -> ImageTexture:
	if _slash_tex != null:
		return _slash_tex
	var s := 192
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(s) * 0.5
	var sweep := 3.4
	var a0 := -sweep * 0.5
	var rin := 0.60
	var rout := 0.86     # 留在 quad 内部：贴到 1.0 会被方边切成直愣愣的两条
	for y in s:
		for x in s:
			var dx := float(x) - c + 0.5
			var dy := float(y) - c + 0.5
			var r := sqrt(dx * dx + dy * dy) / c
			if r > rout or r < rin:
				continue
			var ang := atan2(dy, dx)
			var t := (ang - a0) / sweep
			if t < 0.0 or t > 1.0:
				continue
			var u := (r - rin) / (rout - rin)
			var band := pow(sin(PI * u), 0.9)              # 窄带，内外软边
			var edge := 0.72 + 0.28 * u                    # 外沿略亮做刃口
			var tip := pow(sin(PI * t), 0.5)               # 两端渐隐，中段基本满亮
			var a := band * edge * tip
			if a > 0.01:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_slash_tex = ImageTexture.create_from_image(img)
	return _slash_tex


# ---- 风痕条：横向软边亮带（冲刺拖尾用）----
static func streak_texture() -> ImageTexture:
	if _streak_tex != null:
		return _streak_tex
	var w := 128
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var u := float(x) / float(w - 1) * 2.0 - 1.0     # -1..1
			var v := float(y) / float(h - 1) * 2.0 - 1.0
			var long := pow(clampf(1.0 - absf(u), 0.0, 1.0), 1.6)
			var thick := pow(clampf(1.0 - absf(v), 0.0, 1.0), 2.2)
			var a := long * thick
			if a > 0.01:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_streak_tex = ImageTexture.create_from_image(img)
	return _streak_tex


# ---- 贴图：径向裂纹（暗色）与软边光环（白色，靠 albedo_color 上色） ----
static func crack_texture() -> ImageTexture:
	if _crack_tex != null:
		return _crack_tex
	var s := CRACK_SIDE
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260828
	var c := float(s) * 0.5
	var maxr := c - 6.0
	# 主裂纹：粗、黑、边缘带一点渐隐，斜视角也看得见
	for branch in 10:
		var ang := TAU * float(branch) / 10.0 + rng.randf_range(-0.24, 0.24)
		var r := 6.0
		var wob := rng.randf_range(0.05, 0.15) * (1.0 if branch % 2 == 0 else -1.0)
		while r < maxr:
			ang += wob * rng.randf_range(-1.0, 1.6)
			var px := c + cos(ang) * r
			var py := c + sin(ang) * r
			var t := r / maxr
			_stamp(img, px, py, lerpf(7.5, 1.6, t), Color(0.05, 0.04, 0.05, lerpf(1.0, 0.5, t)))
			if rng.randf() < 0.06 and r > maxr * 0.22:            # 岔叉
				var sang := ang + rng.randf_range(-1.2, 1.2)
				var sr := 0.0
				var slen := maxr * 0.34
				while sr < slen:
					sang += rng.randf_range(-0.3, 0.3) * 0.4
					sr += 1.2
					var st := sr / slen
					_stamp(img, px + cos(sang) * sr, py + sin(sang) * sr, lerpf(4.2, 1.0, st),
						Color(0.06, 0.05, 0.06, lerpf(0.85, 0.25, st)))
			r += 1.1
	# 中心砸坑：暗芯 + 一圈更深的裂口边
	_stamp(img, c, c, 22.0, Color(0.10, 0.08, 0.09, 0.55))
	_stamp(img, c, c, 14.0, Color(0.04, 0.03, 0.04, 0.95))
	# 崩出的碎屑：砸坑外围若干小黑点
	for i in 26:
		var da := rng.randf() * TAU
		var dr := rng.randf_range(26.0, maxr * 0.92)
		_stamp(img, c + cos(da) * dr, c + sin(da) * dr, rng.randf_range(1.2, 2.6),
			Color(0.08, 0.07, 0.08, rng.randf_range(0.35, 0.8)))
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex


static func ring_texture() -> ImageTexture:
	if _ring_tex != null:
		return _ring_tex
	var s := 224
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(s) * 0.5
	for y in s:
		for x in s:
			var dx := float(x) - c + 0.5
			var dy := float(y) - c + 0.5
			var r := sqrt(dx * dx + dy * dy) / c
			if r > 1.0:
				continue
			# 外缘一道粗实圈 + 内侧一道细圈 + 极淡的危险区填充
			var rim := clampf(1.0 - absf(r - 0.93) / 0.075, 0.0, 1.0)
			var inner := clampf(1.0 - absf(r - 0.66) / 0.035, 0.0, 1.0) * 0.6
			var fill := (1.0 - r) * 0.16
			var a := maxf(rim, maxf(inner, fill))
			if a > 0.01:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_ring_tex = ImageTexture.create_from_image(img)
	return _ring_tex


static func _stamp(img: Image, cx: float, cy: float, rad: float, col: Color) -> void:
	## 在整数像素上盖一个软边圆点（画裂纹用）：越靠边缘越透明，避免锯齿硬边
	var x0 := maxi(int(cx - rad - 1), 0)
	var x1 := mini(int(cx + rad + 2), img.get_width() - 1)
	var y0 := maxi(int(cy - rad - 1), 0)
	var y1 := mini(int(cy + rad + 2), img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := sqrt(float(x - cx) * float(x - cx) + float(y - cy) * float(y - cy))
			if d > rad:
				continue
			var a := col.a * clampf(1.0 - (d / maxf(rad, 0.001)) * 0.7, 0.0, 1.0)
			var old := img.get_pixel(x, y)
			# 同一条纹路上反复盖点不该越叠越黑，取较不透明者
			if a > old.a:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
