extends Node3D
## 联机飞行物"复制体"：只负责在**别人的机器上**把箭/魔法球的样子演出来。
## 伤害仍然只在射手那台机器判定并上报房主结算，这里没有任何碰撞与伤害逻辑，
## 所以复制体不建碰撞体、不进任何分组，纯视觉，寿命到了自己回收。
var _vel := Vector3.ZERO
var _grav := 0.0
var _life := 3.0
var _age := 0.0
var _kind := "orb"
# 冰冻术队形：一个虚拟圆心沿 dir 匀速前进，球绕它转
var _orbit := false
var _center := Vector3.ZERO
var _dir := Vector3.FORWARD
var _speed := 0.0
var _form_r := 0.0
var _omega := 0.0
var _phase := 0.0
var _bx := Vector3.RIGHT
var _by := Vector3.UP
static func spawn(parent: Node, kind: String, pos: Vector3, vel: Vector3, payload: Dictionary = {}) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var n := Node3D.new()
	n.set_script(preload("res://scripts/pvp/pvp_replica.gd"))
	n.name = "Replica"
	parent.add_child(n)
	n._begin(kind, pos, vel, payload)
func _begin(kind: String, pos: Vector3, vel: Vector3, payload: Dictionary) -> void:
	_kind = kind
	global_position = pos
	_vel = vel
	_life = float(payload.get("life", 3.0))
	match kind:
		"arrow":
			_build_arrow(Color(0.45, 0.32, 0.16))
			_grav = 16.0
		"arrow_homing":
			_build_arrow(Color(0.85, 0.75, 0.35))
			_grav = 4.0
		"ice":
			_build_orb(payload.get("color", Color(0.45, 0.8, 1.0)), float(payload.get("radius", 0.16)), 2.4)
			_orbit = true
			_center = pos
			_dir = Vector3(payload.get("dir", Vector3.FORWARD)).normalized()
			_speed = float(payload.get("speed", 16.0))
			_form_r = float(payload.get("form_r", 0.35))
			_omega = float(payload.get("omega", 6.0))
			_phase = float(payload.get("phase", 0.0))
			var up := Vector3.UP if absf(_dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
			_bx = _dir.cross(up).normalized()
			_by = _dir.cross(_bx).normalized()
		_:
			_build_orb(payload.get("color", Color(1.0, 0.35, 0.12)), float(payload.get("radius", 0.18)),
				float(payload.get("glow", 2.2)))
			_grav = float(payload.get("gravity", 9.8))
	_orient()
func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= _life or not is_inside_tree():
		queue_free()
		return
	if _orbit:
		# 圆心匀速前进，球绕轴转：和真冰球同一套公式，队形看起来一致
		_center += _dir * _speed * delta
		var ang := _phase + _omega * _age
		global_position = _center + (_bx * cos(ang) + _by * sin(ang)) * _form_r
		return
	_vel.y -= _grav * delta
	global_position += _vel * delta
	_orient()
func _orient() -> void:
	if _vel.length_squared() < 0.0001:
		return
	if _kind == "arrow" or _kind == "arrow_homing":
		# 箭杆沿飞行方向（模型本身朝 -Z 建，所以用 -vel 定 forward）
		look_at(global_position - _vel.normalized(), Vector3.UP)
	else:
		rotate_y(delta_rot())
var _spin := 0.0
func delta_rot() -> float:
	_spin += 0.25
	return _spin
func _build_arrow(shaft_col: Color) -> void:
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.016
	cm.bottom_radius = 0.016
	cm.height = 0.72
	shaft.mesh = cm
	shaft.rotation_degrees = Vector3(90, 0, 0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = shaft_col
	smat.roughness = 0.7
	shaft.material_override = smat
	add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.03, 0.03, 0.12)
	head.mesh = hm
	head.position = Vector3(0, 0, -0.4)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.8, 0.82, 0.86)
	hmat.metallic = 0.8
	head.material_override = hmat
	add_child(head)
	var fletch := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.09, 0.02, 0.14)
	fletch.mesh = fm
	fletch.position = Vector3(0, 0, 0.3)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.9, 0.88, 0.82)
	fletch.material_override = fmat
	add_child(fletch)
	_no_shadow()
func _build_orb(col: Color, r: float, glow: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = maxf(r, 0.04)
	sm.height = maxf(r, 0.04) * 2.0
	sm.radial_steps = 12
	sm.rings = 8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, 0.92)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = glow
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	# 外圈光晕：比本体大一圈的半透明壳，远距离也能看出是一团光
	var halo := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = maxf(r, 0.04) * 1.55
	hs.height = maxf(r, 0.04) * 3.1
	hs.radial_steps = 12
	hs.rings = 8
	halo.mesh = hs
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(col.r, col.g, col.b, 0.22)
	hm.emission_enabled = true
	hm.emission = col
	hm.emission_energy_multiplier = glow * 0.6
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo.material_override = hm
	add_child(halo)
	_no_shadow()
func _no_shadow() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
