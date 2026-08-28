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

var _t := 0.0
var _radius := 6.0
var _tint := Color(1, 1, 1)
var _want_crack := true
var _wave_life := -1.0
var _crack: MeshInstance3D
var _wave: MeshInstance3D
var _crack_mat: StandardMaterial3D
var _wave_mat: StandardMaterial3D


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


func _ready() -> void:
	add_to_group("slam_fx")
	# 地裂：贴地的方形面片（暗色裂纹，抬 0.02 防与地面穿模）
	if _want_crack:
		_crack = _make_quad(crack_texture(), _radius * 2.0, 0.02)
		_crack_mat = _crack.material_override as StandardMaterial3D
		_crack.scale = Vector3(0.55, 1.0, 0.55)
	# 扩散光环：从中心快速推出去
	_wave = _make_quad(ring_texture(), _radius * 2.6, 0.05)
	_wave_mat = _wave.material_override as StandardMaterial3D
	_wave.scale = Vector3(0.12, 1.0, 0.12)


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
