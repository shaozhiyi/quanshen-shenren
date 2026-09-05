extends Node3D
## 第三武器·法杖（挂在相机下，由 player.gd 用 C 在已装备武器间循环切换）。
## 交互：点一下 X（或鼠标左键）→ 甩杖射出一颗魔法球；按住不放 → 蓄力，最多 3 秒，
##       松手射出"更大的球"（蓄满才算蓄力弹）。点射与蓄力共用同一个 2 秒冷却。
## 球的颜色在起手那一刻随机决定（杖顶光球当场透出这个颜色）：
##   红球＝纯伤害 80（蓄满 140）
##   蓝球＝伤害 50（蓄满 90）+ 把 BOSS 定身 1 秒（蓄满 1.5 秒）；定身只冻结推进，不打断当前动作
## 数值全部集中在下面这一段常量里，改平衡只动这里。
## 模型：Poly Pizza CC0「Staff」（assets/weapons/staff.glb，见 CREDITS.txt）；
##       杖顶光球与挥杖动画都是程序化的（本素材包没有施法动画）。

const STAFF_MODEL := preload("res://assets/weapons/staff.glb")
const ORB_SCRIPT := preload("res://scripts/staff_orb.gd")

# ---- 可改数值：冷却与蓄力 ----
const SHOT_COOLDOWN := 2.0        # 每次出手后的冷却（秒），点射与蓄力共用
const CHARGE_MAX := 3.0           # 蓄满所需秒数
const CHARGE_DONE := 0.99         # 蓄力比例到多少算"蓄满"（松手出大球）
const SWING_TIME := 0.26          # 甩杖动画时长
const SPEED := 26.0               # 球速 m/s
const SPEED_CHARGED := 30.0

# ---- 可改数值：伤害与控制（进背包强化前的小基数） ----
const DMG_RED := 80               # 红球伤害
const DMG_BLUE := 50              # 蓝球伤害
const DMG_RED_CHARGED := 140      # 蓄满红球伤害
const DMG_BLUE_CHARGED := 90      # 蓄满蓝球伤害
const CONTROL_SEC := 1.0          # 蓝球定身秒数
const CONTROL_SEC_CHARGED := 1.5  # 蓄满蓝球定身秒数
const ORB_R := 0.13               # 普通球半径（米）
const ORB_R_CHARGED := 0.26       # 蓄满球半径（更大的球）
const RED_COLOR := Color(1.0, 0.18, 0.14)
const BLUE_COLOR := Color(0.22, 0.55, 1.0)
const IDLE_GEM := Color(0.78, 0.70, 1.0)   # 未起手时杖顶宝石的中性色
const BLUE_CHANCE := 0.5          # 出蓝球的概率（其余为红）

# ---- 视图模型摆放（相机局部坐标） ----
const MODEL_SCALE := 0.24
const HOLD_POS := Vector3(0.40, -0.38, -0.62)
const HOLD_ROT := Vector3(-6.0, 14.0, 22.0)

var active := false
var _camera: Camera3D
var _space: Node3D
var _model: Node                                  # staff.glb 的实例根
var _tip_mesh: MeshInstance3D                     # 用来定位杖尖的那个网格
var _tip_vertex := Vector3.ZERO                   # 网格本地坐标里的最高点 = 杖尖
var _tip: Node3D
var _tip_orb: MeshInstance3D
var _tip_mat: StandardMaterial3D
var _charging := false
var _charge := 0.0
var _cooldown := 0.0
var _swing := 0.0                 # >0 表示甩杖动画进行中，剩余秒
var _hold_lmb := false
var _hold_x := false
var _next_blue := false           # 起手时就定好这一发是红还是蓝
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_camera = get_parent() as Camera3D
	_build()
	set_active(false)


func _build() -> void:
	_space = Node3D.new()
	_space.scale = Vector3.ONE * MODEL_SCALE
	add_child(_space)
	# 注意：要把 GLB 的实例根挂进来，不能只挂里面那个 MeshInstance3D（它还认着原来的爹）
	_model = STAFF_MODEL.instantiate()
	_space.add_child(_model)
	var mi := _find_mesh(_model)
	if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		_tip_mesh = mi
		_tip_vertex = _top_vertex(mi)          # 模型本地坐标里的最高点
	_place_tip()
	# 杖顶光球：蓄力时变大变亮，颜色就是这一发的颜色
	_tip_mat = StandardMaterial3D.new()
	_tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tip_mat.emission_enabled = true
	_tip_mat.albedo_color = Color(1, 1, 1, 0.9)
	_tip_mat.emission = IDLE_GEM
	_tip_mat.emission_energy_multiplier = 1.4
	_tip_orb = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	s.radial_segments = 10
	s.rings = 6
	_tip_orb.mesh = s
	_tip_orb.material_override = _tip_mat
	_tip_orb.scale = Vector3.ONE * 0.42
	_tip.add_child(_tip_orb)


## 把杖尖换算到 _space 的本地坐标（要等进树之后 global_transform 才有意义）
func _place_tip() -> void:
	if _tip != null or _space == null:
		return
	_tip = Node3D.new()
	if _tip_mesh != null:
		_tip.position = _space.to_local(_tip_mesh.global_transform * _tip_vertex)
	_space.add_child(_tip)


func _top_vertex(mi: MeshInstance3D) -> Vector3:
	## 在模型本地坐标里找最高点，作为"球从这里飞出去"的出口
	var best := Vector3.ZERO
	var best_y := -1e9
	var m := mi.mesh
	if m == null or m.get_surface_count() == 0:
		return best
	var arr: Array = m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for v in verts:
		if v.y > best_y:
			best_y = v.y
			best = v
	return best


func _find_mesh(n: Node) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D:
			return c as MeshInstance3D
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


# ---- 对外接口（player / HUD 用） ----
func set_active(a: bool) -> void:
	active = a
	visible = a
	if not a:
		_cancel()
		_swing = 0.0
		position = HOLD_POS
		rotation_degrees = HOLD_ROT


func is_active() -> bool:
	return active


func is_charging() -> bool:
	return _charging


func is_attacking() -> bool:
	## 甩杖动画进行中：这段时间 C 被 player.weapon_busy() 拦住
	return _swing > 0.0


func charge_ratio() -> float:
	## 0..1，供 HUD 蓄力条读取
	if not _charging:
		return 0.0
	return clampf(_charge / CHARGE_MAX, 0.0, 1.0)


func is_fully_charged() -> bool:
	return _charging and charge_ratio() >= CHARGE_DONE


func shot_cooldown() -> float:
	## 冷却时长（与 bow.gd 同名同义，HUD 用一套调用问两把武器）
	return SHOT_COOLDOWN


func cooldown_left() -> float:
	## 还要等多久才能出手（秒）
	return _cooldown


func charge_time() -> float:
	## 蓄满所需秒数（与 bow.gd 同名同义）
	return CHARGE_MAX


func charge_max() -> float:
	return CHARGE_MAX


func cooldown_time() -> float:
	return SHOT_COOLDOWN


func damage_range() -> Array:
	## 供 HUD 显示：[点射红球, 蓄满红球]（常量没法 call，这里包一层）
	return [DMG_RED, DMG_RED_CHARGED]


func blue_range() -> Array:
	## 蓝球两档伤害
	return [DMG_BLUE, DMG_BLUE_CHARGED]


func enhanced_range() -> Array:
	## HUD 用的实际伤害（已含强化倍率并向下取整）：[点射红球, 蓄满红球]
	return [power(DMG_RED), power(DMG_RED_CHARGED)]


func shot_plan() -> Dictionary:
	## 这一发会是什么（起手时即确定，HUD/自检都读它，保证"看到的=打出的"）
	var full := is_fully_charged()
	var base := DMG_RED
	if _next_blue:
		base = DMG_BLUE_CHARGED if full else DMG_BLUE
	else:
		base = DMG_RED_CHARGED if full else DMG_RED
	return {
		"blue": _next_blue,
		"charged": full,
		"damage": power(base),
		"control": (CONTROL_SEC_CHARGED if full else CONTROL_SEC) if _next_blue else 0.0,
		"radius": ORB_R_CHARGED if full else ORB_R,
		"color": BLUE_COLOR if _next_blue else RED_COLOR,
	}


func power(base: int) -> int:
	## 底数 × 法杖强化倍率，向下取整（与剑/弓同一口径）
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("attack_power"):
		return int(p.call("attack_power", "staff", float(base)))
	return int(floor(float(base) * 1.0))


# ---- 输入：点一下=直接射，按住=蓄力，松手=射；与弓一样认左键和 X 两个键 ----
func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_hold("lmb", event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventKey and not event.echo and event.keycode == KEY_X:
		_set_hold("x", event.pressed)


func _set_hold(who: String, on: bool) -> void:
	if who == "lmb":
		_hold_lmb = on
	else:
		_hold_x = on
	var want := _hold_lmb or _hold_x
	if want and not _charging:
		if _cooldown > 0.0 or _swing > 0.0:
			return                 # 冷却中 / 上一发还在甩：不起手
		_charging = true
		_charge = 0.0
		_next_blue = _rng.randf() < BLUE_CHANCE   # 起手定色，杖顶光球立刻透出这一发的颜色
	elif not want and _charging:
		_fire()


func _cancel() -> void:
	_charging = false
	_charge = 0.0
	_hold_lmb = false
	_hold_x = false


func _fire() -> void:
	var plan := shot_plan()
	_cancel()
	_cooldown = SHOT_COOLDOWN
	_swing = SWING_TIME
	if _camera == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	var f := -_camera.global_transform.basis.z.normalized()
	# 出口优先用杖尖的世界坐标（球看着从杖头飞出去），再沿视线推一点避免贴脸命中
	var origin: Vector3 = (_tip.global_position if _tip != null else global_position) + f * 0.35
	ORB_SCRIPT.spawn(scene, origin, f,
		float(SPEED_CHARGED if bool(plan.charged) else SPEED),
		int(plan.damage), plan.color, float(plan.radius), float(plan.control))


func _process(delta: float) -> void:
	if not active:
		return
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if _charging:
		_charge = minf(_charge + delta, CHARGE_MAX)
	if _swing > 0.0:
		_swing = maxf(0.0, _swing - delta)

	# 甩杖：绕 X 往前下方压一下再回位（sin 曲线，起手到收尾一气呵成）
	var k := 0.0
	if _swing > 0.0:
		k = sin((1.0 - _swing / SWING_TIME) * PI)
	position = HOLD_POS + Vector3(-0.05 * k, 0.09 * k, -0.14 * k)
	rotation_degrees = Vector3(HOLD_ROT.x - 46.0 * k, HOLD_ROT.y, HOLD_ROT.z + 14.0 * k)

	# 杖顶光球：待机是中性宝石色，起手后才透出这一发的红/蓝，并随蓄力变大变亮
	var r := charge_ratio()
	var want_scale := lerpf(0.42, 1.15, r)
	if is_fully_charged():
		want_scale *= 1.0 + 0.10 * sin(_charge * 9.0)
	_tip_orb.scale = _tip_orb.scale.lerp(Vector3.ONE * want_scale, minf(1.0, delta * 12.0))
	if _charging or _swing > 0.0:
		_tip_mat.emission = BLUE_COLOR if _next_blue else RED_COLOR
		_tip_mat.emission_energy_multiplier = lerpf(1.8, 4.2, r)
	else:
		_tip_mat.emission = IDLE_GEM
		_tip_mat.emission_energy_multiplier = 1.4
