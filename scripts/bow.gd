extends Node3D
## 副武器·弓（挂在相机下）。主/副武器按 Z 切换，初始主武器为剑。
## 交互：装备弓时，按住鼠标左键 → 进入瞄准（FOV 拉近、弓移到眼前、搭箭、弦随蓄力后拉），
## 3 秒蓄满；松手 → 沿准星方向射出箭。箭为 RigidBody3D，弹道/射程由物理引擎（重力抛物线）决定，
## 初速与攻击力随蓄力提升：满蓄 3s 时攻击力 50（命中 BOSS 扣 50），未满按比例衰减。
## 模型：Poly Pizza CC0 弓 + Quaternius CC0 箭（assets/weapons，见 CREDITS.txt）。

const BOW_MODEL := preload("res://assets/weapons/bow.glb")
const ARROW_MODEL := preload("res://assets/weapons/arrow.glb")
const ARROW_SCRIPT := preload("res://scripts/arrow.gd")

const CHARGE_TIME := 3.0          # 满蓄秒数
const SHOT_COOLDOWN := 0.5        # 每次射出后的等待（秒）
const FULL_DMG := 50              # 满蓄攻击力
const MIN_DMG := 12               # 刚松手的最低攻击力
const SPEED_MIN := 22.0           # 初速 m/s
const SPEED_MAX := 58.0           # 满蓄初速 m/s（决定射程）
const FOV_IDLE := 75.0
const FOV_AIM := 48.0

# 弓模型本地坐标（未缩放）：弦侧 +X，两端弓梢
const TIP_U := Vector3(0.475, 2.34, 0.0)
const TIP_L := Vector3(0.475, -2.34, 0.0)
const NOCK_REST_X := 0.475
const NOCK_DRAW_X := 2.05         # 满拉时弦的 x（向玩家方向后拉）
const BOW_SCALE := 0.1275          # 用户要求放大 50%（原 0.085）

var active := false               # 是否为当前装备武器（由 player 切换）
var _charging := false
var _charge := 0.0                # 秒
var _cooldown := 0.0              # 射击后冷却剩余秒
var _camera: Camera3D
var _bow_space: Node3D
var _strand_u: MeshInstance3D
var _strand_l: MeshInstance3D
var _nocked: Node3D
var _draw := 0.0                  # 0..1 视觉拉弦量


func _ready() -> void:
	_camera = get_parent() as Camera3D
	_build()
	set_active(false)


func set_active(a: bool) -> void:
	active = a
	visible = a
	if not a:
		_cancel()
		if _camera != null:
			_camera.fov = FOV_IDLE


func is_active() -> bool:
	return active


func charge_ratio() -> float:
	## 当前蓄力比例 0..1，供 HUD 蓄力条读取
	if not _charging:
		return 0.0
	return clampf(_charge / CHARGE_TIME, 0.0, 1.0)


func is_charging() -> bool:
	return _charging


# ---- 构建弓视图模型 ----
func _build() -> void:
	_bow_space = Node3D.new()
	_bow_space.rotation_degrees = Vector3(0, -90, 0)   # 弦侧 +X → 世界 +Z（朝玩家）
	_bow_space.scale = Vector3.ONE * BOW_SCALE
	add_child(_bow_space)

	# 弓身：仅保留 surface 0(木身) + 1(握把)，去掉导入的静态弦
	var src: MeshInstance3D = _find_mesh(BOW_MODEL.instantiate())
	var out := ArrayMesh.new()
	for i in [0, 1]:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.mesh.surface_get_arrays(i))
		out.surface_set_material(out.get_surface_count() - 1, src.mesh.surface_get_material(i))
	var bow_mi := MeshInstance3D.new()
	bow_mi.mesh = out
	_bow_space.add_child(bow_mi)

	# 动态弦（两段圆柱，本地坐标随拉距更新）
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.83, 0.76)
	smat.roughness = 0.6
	_strand_u = _make_strand(smat)
	_strand_l = _make_strand(smat)
	_bow_space.add_child(_strand_u)
	_bow_space.add_child(_strand_l)

	# 搭在弦上的箭（沿本地 X，箭尖朝 -X 前方，箭尾落在弦上、略高于握把）
	_nocked = Node3D.new()
	_nocked.rotation_degrees = Vector3(0, 180, 0)
	var av := _arrow_visuals()
	_nocked.add_child(av)
	_bow_space.add_child(_nocked)


func _make_strand(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 1.0
	cyl.material = mat
	mi.mesh = cyl
	return mi


func _arrow_visuals() -> Node3D:
	return ARROW_MODEL.instantiate()


# ---- 输入：按住左键蓄力，松手发射 ----
func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _cooldown <= 0.0:
				_charging = true
				_charge = 0.0
		else:
			if _charging:
				_fire()


func _cancel() -> void:
	_charging = false
	_charge = 0.0
	_draw = 0.0


func _fire() -> void:
	var ratio := clampf(_charge / CHARGE_TIME, 0.0, 1.0)
	var speed := lerpf(SPEED_MIN, SPEED_MAX, ratio)
	var dmg := int(round(lerpf(float(MIN_DMG), float(FULL_DMG), ratio) * _player_damage_scale()))
	_cancel()
	_cooldown = SHOT_COOLDOWN
	if _camera == null:
		return
	var f := -_camera.global_transform.basis.z.normalized()
	var origin := _camera.global_position + f * 0.45
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	ARROW_SCRIPT.spawn(scene, _camera.global_transform.basis, origin, speed, dmg)


func _player_damage_scale() -> float:
	## 弓的强化倍率（每件装备单独算，只认"弓箭 +N"）；玩家按分组取，取不到按 1.0
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("damage_scale_for"):
		return float(p.call("damage_scale_for", "bow"))
	return 1.0


func _process(delta: float) -> void:
	if not active or _camera == null:
		return
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if _charging:
		_charge = minf(_charge + delta, CHARGE_TIME)
	_draw = lerpf(_draw, charge_ratio(), minf(1.0, delta * 12.0))

	# 瞄准 FOV 拉近/还原
	var target_fov := lerpf(FOV_IDLE, FOV_AIM, _draw)
	_camera.fov = lerpf(_camera.fov, target_fov, minf(1.0, delta * 10.0))

	# 弓身随瞄准下沉到眼前（相机局部坐标）
	var idle_p := Vector3(0.42, -0.36, -0.6)
	var aim_p := Vector3(0.16, -0.26, -0.52)
	position = idle_p.lerp(aim_p, _draw)
	rotation_degrees = Vector3(0, lerpf(-10.0, 0.0, _draw), 0)

	# 弦与搭箭随拉距更新（本地坐标；箭高 y=0.5，箭尾贴弦）
	var nock_x := lerpf(NOCK_REST_X, NOCK_DRAW_X, _draw)
	var nock := Vector3(nock_x, 0.5, 0)
	_strand_u.transform = _strand_xform(TIP_U, nock)
	_strand_l.transform = _strand_xform(TIP_L, nock)
	_nocked.position = Vector3(nock_x - 0.82, 0.5, 0)
	_nocked.visible = _draw > 0.02


func _strand_xform(a: Vector3, b: Vector3) -> Transform3D:
	var y := b - a
	var ln := y.length()
	if ln < 0.0001:
		return Transform3D()
	var yn := y / ln
	var ref := Vector3(1, 0, 0) if absf(yn.y) < 0.9 else Vector3(0, 0, 1)
	var x := ref.cross(yn).normalized()
	var z := x.cross(yn)
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _find_mesh(n: Node) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D:
			return c as MeshInstance3D
		var r := _find_mesh(c)
		if r != null:
			return r
	return null
