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

signal action(kind: String)   # 联机：起手动作（"charge"/"swing"），别人要看到甩杖蓄力

const STAFF_MODEL := preload("res://assets/weapons/staff.glb")
const ORB_SCRIPT := preload("res://scripts/staff_orb.gd")

# ---- 可改数值：冷却与蓄力 ----
const SHOT_COOLDOWN := 3.0        # 每次出手后的冷却（秒），点射与蓄力共用（攻击间隔：不能攻击也不能切）
const CHARGE_MAX := 4.0           # 蓄满所需秒数
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

# ---- 技能·火球术（数字 1）：一颗火属性大球，冷却 15 秒，耗 70 法力 ----
# 球体比满蓄球大 2 倍、伤害 1.8 倍满蓄伤害（同样吃强化）；火球不带定身。
# 放完有 4 秒硬直（SKILL_LOCK）：只锁攻击——技能冷却期间切武器照常（攻击间隔才锁切换）。
const SKILL_NAME := "火球术"
const SKILL_CD := 15.0
const SKILL_MP := 70
const SKILL_DMG_MULT := 1.8       # 伤害 = 满蓄伤害 ×1.8
const SKILL_R_MULT := 2.0         # 半径 = 满蓄球 ×2
const SKILL_LOCK := 4.0           # 放完后的硬直秒数
const FIRE_COLOR := Color(1.0, 0.42, 0.08)   # 火球与杖顶辉光的火色
const FIRE_SPEED := 30.0          # 火球速度 = 满蓄球速

# ---- 技能·冰冻术（数字 2）：按住 2 蓄力、松手甩出三颗冰球，冷却 20 秒，耗 80 法力 ----
# 冰球判定与普攻同款（伤害+定身、只控制不打断），但定身可以往上叠；蓄满则伤更高控更久。
# 三颗球绕出手轴排成正三角、飞行途中旋转。与火球术各自独立冷却（所有技能都不共享冷却），
# 蓄力共用一套状态——蓄力期间照旧不能切武器。
const SKILL2_NAME := "冰冻术"
const SKILL2_CD := 20.0
const SKILL2_MP := 80
const ICE_COLOR := Color(0.55, 0.85, 1.0)
const ICE_COUNT := 3              # 一次甩出三颗
const ICE_FORM_R := 0.55          # 三角编队半径（米）
const ICE_SPIN := 5.0             # 编队自转角速度（弧度/秒）

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
var _cooldown := 0.0              # 普攻攻击间隔（点射/蓄力/冰冻出手后；期间不能攻击也不能切）
var _skill_lock := 0.0            # 火球放完的 4 秒硬直：只锁攻击，不拦切武器
var _skill_cd := 0.0              # 火球术冷却剩余秒（切走了也继续跳）
var _skill2_cd := 0.0             # 冰冻术冷却剩余秒（切走了也继续跳）
var _fire_glow := false           # 这一甩是火球术：杖顶辉光透火色
var _ice_glow := false            # 这一甩是冰冻术：杖顶辉光透冰色
var _hold_2 := false              # 数字 2 还按着（冰冻术的蓄力源）
var _charge_skill2 := false       # 这次蓄力是冰冻术（松手放三冰球而不是普通球）
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


func visual_root() -> Node3D:
	## 联机：远程玩家复制这份网格当"别人看得见的法杖"
	return _space


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


func blue_enhanced_range() -> Array:
	## HUD 用的蓝球实际伤害（同样吃强化倍率）：[点射, 蓄满]
	## 早先 HUD 直接读 blue_range()（常量），结果强化后红球数字涨了、蓝球还写着底数，
	## 打出去却是强化过的——看到的≠打出的，所以这里补一个和 enhanced_range 同口径的版本。
	return [power(DMG_BLUE), power(DMG_BLUE_CHARGED)]


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


# ---- 技能·火球术（数字 1）----
func cast_skill() -> bool:
	## 甩杖丢出一颗火球：比满蓄球大 2 倍、伤害 1.8 倍满蓄（都吃强化），不带定身。
	## 冷却 15 秒、耗 70 蓝；放完 4 秒硬直记在普攻的 _cooldown 上（不能普攻不能切）。
	## 正在蓄力也照放（那一发的蓄力作废，直接改出火球）。
	if not active or _skill_cd > 0.0 or _camera == null:
		return false
	var p := get_tree().get_first_node_in_group("player")
	if p != null and not bool(p.call("spend_mp", float(SKILL_MP))):
		return false        # 蓝不够：spend_mp 自带判定，扣了才返回 true
	_skill_cd = SKILL_CD
	_cancel()
	_skill_lock = SKILL_LOCK   # 4 秒硬直：只锁攻击；切武器照常（技能冷却不拦切换）
	_swing = SWING_TIME
	action.emit("swing")
	_next_blue = false
	_fire_glow = true
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	var f := -_camera.global_transform.basis.z.normalized()
	# 火球比普通球大得多，出口也推得更远（0.9 米）：贴着杖尖出会让它糊满整个画面
	var origin: Vector3 = (_tip.global_position if _tip != null else global_position) + f * 0.9
	ORB_SCRIPT.spawn(scene, origin, f, FIRE_SPEED, skill_damage(),
		FIRE_COLOR, ORB_R_CHARGED * SKILL_R_MULT, 0.0, "法杖火球术", _thrower())
	_pvp_fx("orb", origin, f * FIRE_SPEED, {
		"color": FIRE_COLOR, "radius": ORB_R_CHARGED * SKILL_R_MULT, "glow": 3.2, "gravity": 0.0})
	return true


func _pvp_fx(kind: String, pos: Vector3, vel: Vector3, payload: Dictionary) -> void:
	## 联机：把这一发的"样子"广播给其他玩家（伤害仍只在射手机器判定、房主结算）
	var shooter := _thrower()
	if shooter != null and shooter.has_method("broadcast_fx"):
		shooter.call("broadcast_fx", kind, pos, vel, payload)


func skill_name() -> String:
	return SKILL_NAME


func skill_cost() -> int:
	return SKILL_MP


func skill_cooldown() -> float:
	return SKILL_CD


func skill_cooldown_left() -> float:
	return _skill_cd


func skill_damage() -> int:
	## 火球伤害 = 满蓄伤害 ×1.8（含强化、向下取整）；结算与 HUD 同一个数
	return int(floor(float(power(DMG_RED_CHARGED)) * SKILL_DMG_MULT))


func skill_desc() -> String:
	return "%d伤·大2倍·无定身" % skill_damage()


# ---- 技能 2·冰冻术（HUD 读这套）----
func skill2_name() -> String:
	return SKILL2_NAME


func skill2_cost() -> int:
	return SKILL2_MP


func skill2_cooldown() -> float:
	return SKILL2_CD


func skill2_cooldown_left() -> float:
	return _skill2_cd


func skill2_damage(full: bool) -> int:
	## 单颗冰球的伤害（判定与蓝球同款、吃强化）
	return power(DMG_BLUE_CHARGED if full else DMG_BLUE)


func skill2_desc() -> String:
	return "三冰球·可叠控（蓄满%d伤/颗）" % skill2_damage(true)


func skill2_ready() -> bool:
	if _skill2_cd > 0.0:
		return false
	var p := get_tree().get_first_node_in_group("player")
	return p == null or bool(p.call("has_mp", float(SKILL2_MP)))


func skill_ready() -> bool:
	if _skill_cd > 0.0:
		return false
	var p := get_tree().get_first_node_in_group("player")
	return p == null or bool(p.call("has_mp", float(SKILL_MP)))


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
	elif who == "x":
		_hold_x = on
	else:
		_hold_2 = on
	var want := _hold_lmb or _hold_x or _hold_2
	if want and not _charging:
		if _cooldown > 0.0 or _skill_lock > 0.0 or _swing > 0.0:
			return                 # 攻击间隔 / 火球硬直 / 上一发还在甩：不起手（切武器不受此限制）
		_charging = true
		_charge = 0.0
		_charge_skill2 = (who == "2")   # 用 2 起手 = 这次蓄的是冰冻术
		if _charge_skill2:
			# 冰冻术起手只验收（冷却/蓝），冷却等真正甩出去那一刻才开始计
			if _skill2_cd > 0.0:
				_charging = false
				_charge_skill2 = false
				return
			var p := get_tree().get_first_node_in_group("player")
			if p != null and not bool(p.call("spend_mp", float(SKILL2_MP))):
				_charging = false
				_charge_skill2 = false
				return
		else:
			_next_blue = _rng.randf() < BLUE_CHANCE   # 起手定色，杖顶光球立刻透出这一发的颜色
		action.emit("charge")
	elif not want and _charging:
		if _charge_skill2:
			_fire_ice(clampf(_charge / CHARGE_MAX, 0.0, 1.0))
		else:
			_fire()


func skill2_hold(pressed: bool) -> void:
	## 数字 2：冰冻术的蓄力源（按住蓄力、松手甩出三冰球），与左键/X 同一套蓄力状态。
	if active:
		_set_hold("2", pressed)


func _fire_ice(ratio: float) -> void:
	## 甩出三颗冰球：判定与普攻同款（伤害+定身），但定身可以往上叠；
	## 蓄满 = 蓝球蓄满档（伤 90、定身 1.5 秒/颗），点按 = 蓝球点按档。三球呈旋转正三角。
	## 冷却从这一刻（真正甩出去）才开始计，蓄力花的时间不算。
	_cancel()
	_skill2_cd = SKILL2_CD
	_cooldown = SHOT_COOLDOWN        # 也算出手：普攻那份冷却照走
	_swing = SWING_TIME              # 攻击动画照放（甩杖甩出一片冰）
	action.emit("swing")
	_ice_glow = true                 # 杖顶透冰色
	var full := ratio >= CHARGE_DONE
	var dmg := power(DMG_BLUE_CHARGED if full else DMG_BLUE)
	var ctrl := CONTROL_SEC_CHARGED if full else CONTROL_SEC
	var scene := get_tree().current_scene
	if scene == null or _camera == null:
		return
	var f := -_camera.global_transform.basis.z.normalized()
	var center := _camera.global_position + f * 1.4
	ORB_SCRIPT.spawn_formation(scene, center, f, SPEED_CHARGED if full else SPEED,
		dmg, ICE_COLOR, ORB_R, ctrl, true, ICE_COUNT, ICE_FORM_R, ICE_SPIN, "法杖冰冻术", _thrower())
	# 三颗冰球逐个广播复制体（同一套绕轴公式，别人看到的队形一致）
	var ice_speed := SPEED_CHARGED if full else SPEED
	for i in ICE_COUNT:
		_pvp_fx("ice", center, f * ice_speed, {
			"color": ICE_COLOR, "radius": ORB_R, "dir": f, "speed": ice_speed,
			"form_r": ICE_FORM_R, "omega": ICE_SPIN, "phase": TAU * float(i) / float(maxi(ICE_COUNT, 1)),
		})


func _cancel() -> void:
	_charging = false
	_charge = 0.0
	_hold_lmb = false
	_hold_x = false
	_hold_2 = false
	_charge_skill2 = false
	_fire_glow = false
	_ice_glow = false


## 联机里按 group 找"第一个玩家"会认错人，直接把相机的主人（玩家本体）传下去
func _thrower() -> PhysicsBody3D:
	return _camera.get_parent() as PhysicsBody3D if _camera != null else null


func _fire() -> void:
	var plan := shot_plan()
	_cancel()
	_cooldown = SHOT_COOLDOWN
	_swing = SWING_TIME
	action.emit("swing")
	if _camera == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	var f := -_camera.global_transform.basis.z.normalized()
	# 出口优先用杖尖的世界坐标（球看着从杖头飞出去），再沿视线推一点避免贴脸命中
	var origin: Vector3 = (_tip.global_position if _tip != null else global_position) + f * 0.35
	var orb_speed := float(SPEED_CHARGED if bool(plan.charged) else SPEED)
	ORB_SCRIPT.spawn(scene, origin, f, orb_speed,
		int(plan.damage), plan.color, float(plan.radius), float(plan.control), "法杖", _thrower())
	_pvp_fx("orb", origin, f * orb_speed, {"color": plan.color, "radius": float(plan.radius)})


func _process(delta: float) -> void:
	if _skill_cd > 0.0:
		_skill_cd = maxf(0.0, _skill_cd - delta)   # 火球冷却不认手上没手上：切走了也照跳
	if _skill2_cd > 0.0:
		_skill2_cd = maxf(0.0, _skill2_cd - delta)
	if not active:
		return
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if _skill_lock > 0.0:
		_skill_lock = maxf(0.0, _skill_lock - delta)
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

	# 杖顶光球：待机是中性宝石色，起手后才透出这一发的红/蓝（火球术透火色），并随蓄力变大变亮
	var r := charge_ratio()
	var want_scale := lerpf(0.42, 1.15, r)
	if is_fully_charged():
		want_scale *= 1.0 + 0.10 * sin(_charge * 9.0)
	_tip_orb.scale = _tip_orb.scale.lerp(Vector3.ONE * want_scale, minf(1.0, delta * 12.0))
	if _charging or _swing > 0.0:
		# 起手/甩杖时杖顶透出这一发的属性色：火球=火色、冰冻术=冰色、普通球=红/蓝
		var glow_col := FIRE_COLOR
		if not _fire_glow:
			glow_col = ICE_COLOR if _ice_glow else (BLUE_COLOR if _next_blue else RED_COLOR)
		var glow_top := 5.6 if _fire_glow else (5.0 if _ice_glow else 4.2)
		_tip_mat.emission = glow_col
		_tip_mat.emission_energy_multiplier = lerpf(1.8, glow_top, maxf(r, 0.5 if (_fire_glow or _ice_glow) else 0.0))
	else:
		_tip_mat.emission = IDLE_GEM
		_tip_mat.emission_energy_multiplier = 1.4
