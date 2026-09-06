extends RigidBody3D
## 法杖弹体：一颗自发光球，直线飞行（不吃重力），命中单位就扣血。
## 红色＝纯伤害；蓝色＝伤害较轻但把 BOSS 定身若干秒（只控制、不打断当前动作）。
## 冰色（冰冻术三连球）＝蓝球同款判定，但定身可以往上叠，且三球绕出手轴排成
## 旋转的正三角飞行。飞行时身后拖一条同色光点尾迹；命中后原地缩掉。
## 数值（伤害/半径/颜色/定身秒数/球速）全在 scripts/staff.gd 顶部，这里只接现成参数。

const MAX_ALIVE := 12            # 同屏上限，超出回收最早那颗
const POP_TIME := 0.14           # 命中后缩没用的秒数

static var _active: Array = []

var dmg := 80
var control_sec := 0.0
var orb_color := Color(1.0, 0.22, 0.20)
var radius := 0.13
var stack_control := false       # 冰冻术的球：定身往上叠（其余球取最长那一次）
var hit_weapon := "法杖"          # 播报用武器名（火球术/冰冻术会带上技能名）
var _hit := false
var _pop := 0.0
var _life := 0.0
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _trail: CPUParticles3D
# 编队旋转（冰冻术三连球）：绕出手轴自转，球与球始终呈正三角
var _orbit_center := Vector3.ZERO
var _orbit_dir := Vector3.ZERO
var _orbit_speed := 0.0
var _orbit_omega := 0.0


static func spawn(parent: Node, origin: Vector3, dir: Vector3, speed: float,
		damage: int, col: Color, r: float, control: float, weapon := "法杖") -> void:
	## 从法杖杖顶射出一颗球：dir 就是相机视线方向（weapon=播报里的武器名）
	_prune()
	while _active.size() >= MAX_ALIVE:
		var old = _active.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var orb := _create(damage, col, r, control, false, weapon)
	parent.add_child(orb)
	orb.global_transform = Transform3D(Basis.IDENTITY, origin)
	orb.linear_velocity = dir.normalized() * speed
	orb._avoid_thrower()
	_active.append(orb)


static func spawn_formation(parent: Node, center: Vector3, dir: Vector3, speed: float,
		damage: int, col: Color, r: float, control: float, stack: bool,
		count: int, form_r: float, omega: float, weapon := "法杖") -> void:
	## 冰冻术：count 颗冰球绕出手轴排成正三角，飞行途中绕轴自转（omega 弧度/秒）。
	## 每颗球仍是独立刚体：速度 = 前进 + 绕轴切向；圆心 = 出手点沿 dir 同速前进，
	## 所以三球全程保持队形，越飞转得越欢。
	_prune()
	while _active.size() >= MAX_ALIVE:
		var old = _active.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	dir = dir.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var bx := dir.cross(up).normalized()
	var by := dir.cross(bx).normalized()
	for i in count:
		var ang := TAU * float(i) / float(maxi(count, 1))
		var off := (bx * cos(ang) + by * sin(ang)) * form_r
		var orb := _create(damage, col, r, control, stack, weapon)
		orb._orbit_center = center
		orb._orbit_dir = dir
		orb._orbit_speed = speed
		orb._orbit_omega = omega
		parent.add_child(orb)
		orb.global_transform = Transform3D(Basis.IDENTITY, center + off)
		orb.linear_velocity = dir * speed
		orb._avoid_thrower()
		_active.append(orb)


static func _create(damage: int, col: Color, r: float, control: float, stack: bool,
		weapon := "法杖") -> RigidBody3D:
	var orb: RigidBody3D = load("res://scripts/staff_orb.gd").new()
	orb.dmg = damage
	orb.orb_color = col
	orb.radius = r
	orb.control_sec = control
	orb.stack_control = stack
	orb.hit_weapon = weapon
	orb._configure()
	return orb


static func _prune() -> void:
	var live: Array = []
	for a in _active:
		if is_instance_valid(a):
			live.append(a)
	_active = live


func _configure() -> void:
	add_to_group("staff_orb")
	mass = 0.2
	gravity_scale = 0.0            # 魔法球直线飞，不掉头
	linear_damp = 0.0              # 工程默认阻尼 0.1 会让球越飞越慢，这里清掉
	angular_damp = 0.0
	continuous_cd = true           # 防高速穿透
	contact_monitor = true
	max_contacts_reported = 2
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	# 与箭同一约定：弹体在层 2，世界/BOSS 在层 1，剑的射线不会被球挡住
	collision_layer = 2
	collision_mask = 1
	_build_visuals()
	var csc := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	csc.shape = sh
	add_child(csc)
	body_entered.connect(_on_body_entered)


func _build_visuals() -> void:
	_core = MeshInstance3D.new()
	_core.mesh = _sphere(radius, 10, 6)
	_core.material_override = _mat(orb_color, 2.4, 1.0)
	add_child(_core)
	# 外圈半透明光晕：让球看着"在发光"而不是一个色块
	_halo = MeshInstance3D.new()
	_halo.mesh = _sphere(radius * 1.7, 10, 6)
	var h := _mat(orb_color, 1.6, 0.30)
	h.cull_mode = BaseMaterial3D.CULL_DISABLED
	h.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo.material_override = h
	add_child(_halo)
	_trail = _make_trail()
	add_child(_trail)


func _sphere(r: float, rings: int, seg: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s


func _mat(col: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	m.metallic = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _make_trail() -> CPUParticles3D:
	## 同色光点尾迹：粒子留在世界坐标里（local_coords=false），球飞过去就留下一条线
	var t := CPUParticles3D.new()
	t.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	t.direction = Vector3.ZERO
	t.spread = 26.0
	t.gravity = Vector3.ZERO
	t.initial_velocity_min = 0.15
	t.initial_velocity_max = 0.7
	t.damping_min = 0.6
	t.damping_max = 1.2
	t.amount = 40
	t.lifetime = 0.34
	t.preprocess = 0.0
	t.emitting = true
	t.local_coords = false
	t.scale_amount_min = radius * 0.5
	t.scale_amount_max = radius * 1.0
	t.color = Color(orb_color.r, orb_color.g, orb_color.b, 1.0)
	# 渐隐用 color_ramp（这里的类型是 Gradient 本体，不是 GPUParticles 的 GradientTexture1D）
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1.0))
	g.add_point(0.45, Color(1, 1, 1, 0.5))
	g.set_color(1, Color(1, 1, 1, 0.0))
	t.color_ramp = g
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.2))
	t.scale_amount_curve = shrink
	# 粒子本体：一颗小发光球（draw_pass_1 是 GPUParticles3D 的写法，这里直接给 mesh）
	t.mesh = _sphere(1.0, 6, 5)
	t.material_override = _mat(orb_color, 2.0, 1.0)
	# 尾迹会散到身后一整条，包围盒要给足，否则会被视锥剔除得看不见
	t.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	return t


func _avoid_thrower() -> void:
	## 出手点就在玩家鼻尖前，把玩家自己排除在碰撞之外（否则出膛即命中）
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p is PhysicsBody3D and (p as Node).is_inside_tree():
		add_collision_exception_with(p as PhysicsBody3D)


func _on_body_entered(other: Node) -> void:
	if _hit:
		return
	_hit = true
	# 往上找带 take_damage 的祖先 = 单位本体（与 arrow.gd 同一套写法）
	var unit: Node = other
	while unit != null and not unit.has_method("take_damage"):
		unit = unit.get_parent()
	if unit != null:
		unit.take_damage(dmg, hit_weapon)
		## 控制类球：只定身，不改 BOSS 的相位/进度；冰冻术的球往上叠
		if control_sec > 0.0 and unit.has_method("stun"):
			unit.call("stun", control_sec, stack_control)
	_pop = POP_TIME
	_trail.emitting = false
	freeze = true
	set_contact_monitor.call_deferred(false)


func _physics_process(delta: float) -> void:
	if _pop > 0.0:
		# 命中收尾：缩掉再收，免得球"粘"在对方身上
		_pop -= delta
		var k := clampf(_pop / POP_TIME, 0.0, 1.0)
		_core.scale = Vector3.ONE * (0.4 + 0.6 * (1.0 - k) + 0.6 * k)
		_halo.scale = Vector3.ONE * (1.0 + 1.6 * (1.0 - k))
		if _pop <= 0.0:
			queue_free()
		return
	if _hit:
		return
	# 编队旋转：绕"圆心 + dir×已飞距离"这根轴转，速度 = 前进 + 切向（大小恒定）
	if _orbit_omega != 0.0:
		var c := _orbit_center + _orbit_dir * (_orbit_speed * _life)
		var rvec := global_position - c
		if rvec.length_squared() > 0.0001:
			var tangent := _orbit_dir.cross(rvec).normalized()
			linear_velocity = _orbit_dir * _orbit_speed + tangent * (_orbit_omega * rvec.length())
	_life += delta
	if global_position.y < -30.0 or _life > 6.0:
		queue_free()


func _exit_tree() -> void:
	_active.erase(self)
