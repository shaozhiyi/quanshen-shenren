extends Node3D
## 副武器·弓（挂在相机下）。主/副武器按 C 切换，初始主武器为剑。
## 交互：装备弓时，按住鼠标左键或 X 键 → 进入瞄准（FOV 拉近、弓移到眼前、搭箭、弦随蓄力后拉），
## 2 秒蓄满；松手 → 沿准星方向射出箭。箭为 RigidBody3D，弹道/射程由物理引擎（重力抛物线）决定，
## 初速与攻击力随蓄力提升：满蓄 2s 时攻击力 70（命中 BOSS 扣 70），未满按比例衰减。
## 蓄力期间不能换武器：player.gd 的 weapon_busy() 会拦住 C，直到松手撒放。
## 模型：Poly Pizza CC0 弓 + Quaternius CC0 箭（assets/weapons，见 CREDITS.txt）。
## 音效：拉弓 assets/audio/bow_draw.wav、放箭 bow_shot.wav（jc-sounds「Fantasy SFX Pack Vol 1」，
##      CC-BY 4.0，见 assets/audio/CREDITS.txt；文件缺失则静默）。满蓄放箭更响（按蓄力比例加音量）。

const BOW_MODEL := preload("res://assets/weapons/bow.glb")
const ARROW_MODEL := preload("res://assets/weapons/arrow.glb")
const ARROW_SCRIPT := preload("res://scripts/arrow.gd")
const SFX := preload("res://scripts/sfx.gd")     # 拉弓 / 射箭音效（素材缺失时自动静默）

const CHARGE_TIME := 2.0          # 满蓄秒数
const SHOT_COOLDOWN := 0.5        # 每次射出后的等待（秒）
const FULL_DMG := 70              # 满蓄攻击力
const MIN_DMG := 12               # 刚松手的最低攻击力
const SPEED_MIN := 22.0           # 初速 m/s
const SPEED_MAX := 58.0           # 满蓄初速 m/s（决定射程）
const FOV_IDLE := 75.0
const FOV_AIM := 48.0

# ---- 技能·快速射击（数字 1）：立刻射出一箭满蓄伤害，冷却 5 秒，耗 30 法力 ----
# 技能冷却期间照常搭弓普射、照常切武器；切走了冷却也继续跳（_process 里不受 active 限制）。
const SKILL_NAME := "快速射击"
const SKILL_CD := 5.0
const SKILL_MP := 30

# ---- 技能·锁定箭（数字 2）：按住 2 蓄力、松手放追踪箭，冷却 12 秒，耗 40 法力 ----
# 伤害 = 1.5 × 同蓄力比例的普射伤害（满蓄 70×1.5=105，吃弓的强化）；箭自己往最近的 BOSS 拐。
# 与快速射击各自独立冷却；蓄力期间照旧不能切武器（同一套蓄力状态）。
const SKILL2_NAME := "锁定箭"
const SKILL2_CD := 12.0
const SKILL2_MP := 40
const SKILL2_DMG_MULT := 1.5

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
var _skill_cd := 0.0              # 快速射击冷却剩余秒（切走了也继续跳）
var _skill2_cd := 0.0             # 锁定箭冷却剩余秒（切走了也继续跳）
var _hold_lmb := false             # 左键还按着
var _hold_x := false               # X 键还按着（与左键等效，任一按住建蓄力）
var _hold_2 := false               # 数字 2 还按着（锁定箭的蓄力源）
var _charge_skill2 := false        # 这次蓄力是锁定箭（松手放追踪箭而不是普通箭）
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


func damage_range() -> Array:
	## 供 HUD 显示：[速射最低伤害, 满蓄伤害]（常量没法 call，这里包一层）
	return [MIN_DMG, FULL_DMG]


func damage_at(ratio: float) -> int:
	## 某个蓄力比例下的实际伤害：底数 × 强化倍率，再向下取整
	## （强化改成指数级之后，结算和 HUD 显示必须走同一个算法，否则数字会对不上）
	var base := lerpf(float(MIN_DMG), float(FULL_DMG), clampf(ratio, 0.0, 1.0))
	return int(floor(base * _player_damage_scale()))


func enhanced_range() -> Array:
	## HUD 显示用的实际伤害区间（已含强化倍率并向下取整）
	return [damage_at(0.0), damage_at(1.0)]


func charge_time() -> float:
	return CHARGE_TIME


func shot_cooldown() -> float:
	return SHOT_COOLDOWN


func cooldown_left() -> float:
	## 还要等多久才能再射（HUD 与法杖共用同一套接口）
	return _cooldown


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


# ---- 输入：按住鼠标左键或 X 键蓄力，松手发射 ----
# 两个输入源各记一份"还按着"：任一按下就起手，最后一个放开才撒放，
# 所以"按住 X 又点一下左键"不会把蓄力清零重来。X 与剑的"按 X 挥砍"不冲突
# （两把武器不会同时 active）。
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
		if _cooldown > 0.0:
			return                       # 冷却中不起手（和原来只认左键时一致）
		_charging = true
		_charge = 0.0
		_charge_skill2 = (who == "2")    # 用 2 起手 = 这次蓄的是锁定箭
		if _charge_skill2:
			# 锁定箭起手就验收：冷却/蓝任一不过就不进蓄力（松手也不会放）
			if _skill2_cd > 0.0:
				_charging = false
				_charge_skill2 = false
				return
			var p := get_tree().get_first_node_in_group("player")
			if p != null and not bool(p.call("spend_mp", float(SKILL2_MP))):
				_charging = false
				_charge_skill2 = false
				return
			_skill2_cd = SKILL2_CD
		SFX.play("draw")                 # 搭弦开拉：只在起势那一刻响
	elif not want and _charging:
		if _charge_skill2:
			_fire_homing(clampf(_charge / CHARGE_TIME, 0.0, 1.0))
		else:
			_fire()


func skill2_hold(pressed: bool) -> void:
	## 数字 2：锁定箭的蓄力源（按住蓄力、松手放），与左键/X 同一套蓄力状态。
	if active:
		_set_hold("2", pressed)


func _fire_homing(ratio: float) -> void:
	## 放追踪箭：伤害 = 1.5 × 同蓄力比例的普射伤害；箭自己往最近的活 BOSS 拐
	_cancel()
	_cooldown = SHOT_COOLDOWN        # 这也算真射了一箭：普射间隔照走
	var speed := lerpf(SPEED_MIN, SPEED_MAX, ratio)
	var dmg := int(floor(float(damage_at(ratio)) * SKILL2_DMG_MULT))
	SFX.play("shot", ratio * 2.5 - 1.0)
	if _camera == null:
		return
	var f := -_camera.global_transform.basis.z.normalized()
	var origin := _camera.global_position + f * 0.45
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	ARROW_SCRIPT.spawn_homing(scene, _camera.global_transform.basis, origin, speed, dmg, _nearest_boss())


func _nearest_boss() -> Node:
	## 最近的活着的目标（锁定箭优先打离自己最近的那只 BOSS；没有就直飞）
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not p.has_method("bosses"):
		return null
	var best: Node = null
	var best_d := 1e12
	for b in p.call("bosses"):
		if b == null or bool(b.call("is_dead")):
			continue
		var d: float = b.global_position.distance_squared_to(_camera.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func _cancel() -> void:
	_charging = false
	_charge = 0.0
	_hold_lmb = false
	_hold_x = false
	_hold_2 = false
	_charge_skill2 = false
	_draw = 0.0


func _fire() -> void:
	var ratio := clampf(_charge / CHARGE_TIME, 0.0, 1.0)
	_cancel()
	_cooldown = SHOT_COOLDOWN
	_release_arrow(ratio)


func _release_arrow(ratio: float) -> void:
	## 沿准星放出一箭：伤害/初速/音效都按蓄力比例来（技能「快速射击」传 1.0 = 满蓄）
	var speed := lerpf(SPEED_MIN, SPEED_MAX, ratio)
	var dmg := damage_at(ratio)
	SFX.play("shot", ratio * 2.5 - 1.0)   # 拉得越满，撒放越响
	if _camera == null:
		return
	var f := -_camera.global_transform.basis.z.normalized()
	var origin := _camera.global_position + f * 0.45
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	ARROW_SCRIPT.spawn(scene, _camera.global_transform.basis, origin, speed, dmg)


# ---- 技能·快速射击（数字 1）----
func cast_skill() -> bool:
	## 立刻射出一箭满蓄伤害的箭：不经过搭弓蓄力，冷却 5 秒、耗 30 法力。
	## 正在蓄力也照放（那一箭的蓄力作废，改出满蓄箭）。
	if not active or _skill_cd > 0.0 or _camera == null:
		return false
	var p := get_tree().get_first_node_in_group("player")
	if p != null and not bool(p.call("spend_mp", float(SKILL_MP))):
		return false        # 蓝不够：spend_mp 自带判定，扣了才返回 true
	_skill_cd = SKILL_CD
	_cancel()
	_cooldown = SHOT_COOLDOWN     # 这也算真的射了一箭：普射的 0.5 秒间隔照走
	_release_arrow(1.0)
	return true


func skill_name() -> String:
	return SKILL_NAME


func skill_cost() -> int:
	return SKILL_MP


func skill_cooldown() -> float:
	return SKILL_CD


func skill_cooldown_left() -> float:
	return _skill_cd


func skill_damage() -> int:
	## 快速射击的伤害 = 满蓄那一档（含强化）
	return damage_at(1.0)


func skill_desc() -> String:
	return "立刻满蓄一箭 %d伤" % skill_damage()


func skill_ready() -> bool:
	if _skill_cd > 0.0:
		return false
	var p := get_tree().get_first_node_in_group("player")
	return p == null or bool(p.call("has_mp", float(SKILL_MP)))


# ---- 技能 2·锁定箭（HUD 读这套）----
func skill2_name() -> String:
	return SKILL2_NAME


func skill2_cost() -> int:
	return SKILL2_MP


func skill2_cooldown() -> float:
	return SKILL2_CD


func skill2_cooldown_left() -> float:
	return _skill2_cd


func skill2_damage(ratio := 1.0) -> int:
	## 锁定箭伤害 = 1.5 × 同蓄力比例的普射伤害（吃弓的强化）
	return int(floor(float(damage_at(ratio)) * SKILL2_DMG_MULT))


func skill2_desc() -> String:
	return "按住蓄力 放追踪箭·最多%d伤" % skill2_damage(1.0)


func skill2_ready() -> bool:
	if _skill2_cd > 0.0:
		return false
	var p := get_tree().get_first_node_in_group("player")
	return p == null or bool(p.call("has_mp", float(SKILL2_MP)))


func _player_damage_scale() -> float:
	## 弓的强化倍率（每件装备单独算，只认"弓箭 +N"）；玩家按分组取，取不到按 1.0
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("damage_scale_for"):
		return float(p.call("damage_scale_for", "bow"))
	return 1.0


func _process(delta: float) -> void:
	if _skill_cd > 0.0:
		_skill_cd = maxf(0.0, _skill_cd - delta)   # 技能冷却切走了也照跳
	if _skill2_cd > 0.0:
		_skill2_cd = maxf(0.0, _skill2_cd - delta)
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
