extends Node3D
## 程序化冲击特效（不依赖任何素材，播完自动 queue_free）：
##   spawn_slam() —— BOSS 砸地：地裂贴图（暗色径向裂纹）+ 一道快速扩散的光环
##   spawn_ring() —— 轻量单圈（玩家二段跳起落点用）
## 贴图用 Image 逐像素画（Godot 的 Image 没有带宽度的画线 API，裂纹用"沿路径盖圆点"实现），
## 生成一次后 static 缓存复用，避免每次砸地都重画 256×256。
## 只做"地裂 + 一圈"两层：纯白场地里加尘圈会在斜视角糊出一大片怪边，反而脏。

const CRACK_SIDE := 256          # 地裂贴图分辨率
const CRACK_LIFE := 2.4          # 地裂残留时长（秒）
const WAVE_LIFE := 0.55          # 扩散光环时长

static var _crack_tex: ImageTexture
static var _ring_tex: ImageTexture
static var _star_tex: ImageTexture

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

# ---- 星点四色：规律固定为红→黄→蓝→绿循环，颜色即效果预告 ----
const STAR_KINDS := ["red", "yellow", "blue", "green"]
const STAR_COLORS := {
	"red": Color(1.0, 0.16, 0.12),
	"yellow": Color(1.0, 0.88, 0.30),
	"blue": Color(0.24, 0.58, 1.0),
	"green": Color(0.26, 0.95, 0.45),
}


static func star_kind(index: int) -> String:
	## 第 index 颗环绕星点对应的颜色种类（红黄蓝绿依次循环）
	return STAR_KINDS[posmod(index, STAR_KINDS.size())]


static func star_color(kind: String) -> Color:
	return STAR_COLORS.get(kind, Color(1, 0.93, 0.62))


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
	fx._speed = speed
	fx._star_life = clampf(life, 0.5, STAR_LIFE_CAP)
	fx._star_size = maxf(size, 0.4) * 1.6     # 20 米外要看得见，放大一档
	fx._kind = kind if STAR_COLORS.has(kind) else "yellow"
	fx._damage = 0.0 if fx._kind == "green" else damage
	fx._heal = 5.0 if fx._kind == "green" else 0.0
	fx._slow = 5.0 if fx._kind == "blue" else 0.0
	fx._base_col = star_color(fx._kind)
	parent.add_child(fx)
	fx.global_position = at


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
		_star_mi = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(_star_size, _star_size)
		_star_mi.mesh = pm
		_star_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = star_texture()
		mat.albedo_color = _base_col
		_star_mi.material_override = mat
		_star_mat = mat
		add_child(_star_mi)
		return
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
