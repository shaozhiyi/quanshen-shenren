extends Node3D
## 第一人称佩剑（X 键戳击）：挥砍动作来自免费 CC0 动捕角色动画
## （Poly Pizza "Sword Slash"，assets/character/king.glb，AnimationPlayer）。
## 原理：隐藏的动画骨架挂在相机下，剑每帧跟随其右手腕骨（Wrist.R）的世界姿态，
## 因此得到真实、流畅的挥砍轨迹；待机时跟随 Idle_Sword 自然呼吸。
## 动态模糊：挥砍期间按延迟显示 3 片剑身残影（记录剑的历史姿态，越旧越淡）。
## 挥剑特效：出手瞬间在相机前方立一片斜月牙剑气（scripts/slam_fx.gd 程序化，无素材）。
## 挥剑音效：assets/audio/sword_swing.wav（含变体随机二选一，CC-BY，见 assets/audio/CREDITS.txt；缺失时静默）。
## slash_hit 信号在挥砍动画 35% 进度处发出，供后续命中判定。
## 挥砍动画播放期间不能换武器：is_attacking() 供 player.gd 的 weapon_busy() 拦 C，
## 收招（动画结束）后才切得动，避免半途换把把这一剑的判定与动画劈成两截。
signal slash_hit
signal skill_hit        # 技能「劈砍」的命中时机（player 据此扣 1.6 倍伤害并定身 1 秒）
signal action(kind: String)   # 联机：起手动作（"slash"/"heavy"/"thrust"），别人要看到挥砍
const SLAM_FX := preload("res://scripts/slam_fx.gd")
const SFX := preload("res://scripts/sfx.gd")
const KNIGHT_SCENE := preload("res://assets/character/king.glb")
const SLASH_ANIM := "CharacterArmature|Sword_Slash"
const IDLE_ANIM := "CharacterArmature|Idle_Sword"
const HAND_BONE := "Wrist.R"
# 骨架相对相机的摆放（让右手落在视野右下）
const RIG_POS := Vector3(0.10, -1.32, -0.72)
const RIG_ROT_DEG := Vector3(0, 150, 0)
# 手腕骨 → 剑柄坐标系的手性修正（由腕骨探针姿态标定：使刃朝前上、护手水平）
var HAND_CORRECTION := Transform3D(
	Basis(
		Vector3(0.148, 0.065, 0.987),
		Vector3(0.046, -0.997, 0.059),
		Vector3(0.988, 0.036, -0.151)
	),
	Vector3(0, 0.02, -0.04)
)
const TRAIL_COUNT := 3
const TRAIL_DELAY := 0.045
# 动作夸张化：以待机腕骨姿态为基准，挥砍偏移的转角/位移增益
const ROT_GAIN := 2.2
const POS_GAIN := 1.4
# ---- 技能·劈砍（数字 1）：1.6 倍攻击 + 定身 1 秒，冷却 10 秒，耗 50 法力 ----
# 技能冷却期间照常普攻、照常切武器；切走了冷却也继续跳（_process 里不受 active 限制）。
const SKILL_NAME := "劈砍"
const SKILL_CD := 10.0
const SKILL_MP := 50
const SKILL_GAIN := 1.6     # 动作幅度增益：比普砍甩得更开（转角/位移一起放大）
const SKILL_SPEED := 0.72   # 动画速度：放慢一点，更沉更用力
const SKILL_SFX_DB := 8.0   # 音效更用力：比普砍响 8dB
const SKILL_FX_SCALE := 1.5 # 剑气放大倍率
const SKILL_FX_COLOR := Color(1.0, 0.84, 0.42)   # 剑气换成重斩的金色
# ---- 技能·突刺（数字 2）：向前戳一记并冲刺穿透，冷却 15 秒，耗 60 法力 ----
# 冲刺位移与"穿透结算（固定 80 + 流血 10 秒）"都在 player.gd（要动玩家坐标）；
# 这里只管起手扣蓝进冷却、戳击的动作与音效。
const SKILL2_NAME := "突刺"
const SKILL2_CD := 15.0
const SKILL2_MP := 60
const SKILL2_ANIM_T := 0.42  # 剑随人前探再收回的动作时长（秒）
const SKILL2_SPEED := 1.5    # 斩击动画加速：戳完立刻收
const SKILL2_SFX_DB := 6.0
var _attacking := false
var _hit_emitted := false
var _skill_swing := false       # 这一剑是不是技能「劈砍」（决定发哪个信号/幅度/音效）
var _gain_scale := 1.0          # 本剑动作夸张化增益（普砍 1.0，劈砍放大）
var _skill_cd := 0.0            # 劈砍冷却剩余秒（切走了也继续跳）
var _skill2_cd := 0.0           # 突刺冷却剩余秒（切走了也继续跳）
var _thrust_anim := 0.0         # 突刺前探动作剩余秒（>0 时骨架整体前探）
var active := true                 # 主武器（默认持剑），Z 切换时由 player 关闭
var _rig: Node
var _anim_player: AnimationPlayer
var _hand_attach: BoneAttachment3D
var _ref_local := Transform3D.IDENTITY   # 腕骨相对骨架的待机基准姿态
var _has_ref := false
var _trails: Array[MeshInstance3D] = []
var _hist: Array[Transform3D] = []
func _ready() -> void:
	_build_grip()
	_build_blade()
	_build_trails()
	_setup_rig()
# ---- 动画骨架：隐藏模型，只取右手腕骨姿态 ----
func _setup_rig() -> void:
	_rig = KNIGHT_SCENE.instantiate()
	_rig.position = RIG_POS
	_rig.rotation_degrees = RIG_ROT_DEG
	get_parent().add_child.call_deferred(_rig)
	await get_tree().process_frame
	# 隐藏全部皮肤网格（保留骨架更新）
	for mi in _find_nodes(_rig, "MeshInstance3D"):
		(mi as MeshInstance3D).visible = false
	var skel := _find_node(_rig, "Skeleton3D") as Skeleton3D
	_anim_player = _find_node(_rig, "AnimationPlayer") as AnimationPlayer
	if skel == null or _anim_player == null:
		push_warning("Sword: 角色骨架/动画播放器缺失，挥砍退化为静止")
		return
	var bone_idx := skel.find_bone(HAND_BONE)
	if bone_idx < 0:
		push_warning("Sword: 找不到骨骼 " + HAND_BONE)
		return
	_hand_attach = BoneAttachment3D.new()
	_hand_attach.bone_idx = bone_idx
	skel.add_child(_hand_attach)
	# 待机动画循环
	var idle: Animation = _anim_player.get_animation(IDLE_ANIM)
	if idle != null:
		idle.loop_mode = Animation.LOOP_LINEAR
	_anim_player.animation_finished.connect(_on_anim_finished)
	_anim_player.play(IDLE_ANIM)
	# 等动画真正求值后再取基准姿态（否则拿到的是 T-pose，会把差值也放大）
	await get_tree().process_frame
	await get_tree().process_frame
	_anim_player.advance(0.0)
	var ref: Transform3D = _rig.global_transform.affine_inverse() * _hand_attach.global_transform
	_ref_local = Transform3D(_norm_basis(ref.basis), ref.origin)
	_has_ref = true
static func _norm_basis(b: Basis) -> Basis:
	return Basis(b.x.normalized(), b.y.normalized(), b.z.normalized())
func _on_anim_finished(_name: String) -> void:
	if _anim_player == null:
		return
	_anim_player.play(IDLE_ANIM)
	_attacking = false
	_hit_emitted = false
	_skill_swing = false
	_gain_scale = 1.0
	_thrust_anim = 0.0
	for t in _trails:
		t.visible = false
	_hist.clear()
func attack() -> void:
	_begin_swing(false)
func visual_root() -> Node3D:
	## 联机：给远程玩家复制"别人看得见的武器"用的可视根（剑的网格直接挂在本节点下）
	return self
func cast_skill() -> bool:
	## 数字 1：技能「劈砍」。冷却中/蓝不够/没在手上 → false（不扣蓝也不动冷却）。
	## 成功：先扣 50 蓝、进 10 秒冷却，再起一记更大更沉的重斩（命中定身由 player 结算）。
	if not active or _skill_cd > 0.0:
		return false
	var p := get_tree().get_first_node_in_group("player")
	if p != null and not bool(p.call("spend_mp", float(SKILL_MP))):
		return false        # 蓝不够：spend_mp 自带判定，扣了才返回 true
	_skill_cd = SKILL_CD
	_begin_swing(true)
	return true
func skill2_hold(pressed: bool) -> void:
	## 数字 2：突刺。按下出招（向前戳一记、人跟着冲过去穿透目标），松开无事。
	## 冲刺/穿透结算在 player.gd（要动玩家坐标）；这里负责动作、音效、扣蓝与冷却。
	if not pressed or not active or _skill2_cd > 0.0:
		return
	var p := get_tree().get_first_node_in_group("player")
	if p != null and not bool(p.call("spend_mp", float(SKILL2_MP))):
		return
	_skill2_cd = SKILL2_CD
	_begin_thrust()
	if p != null and p.has_method("thrust_dash"):
		p.call("thrust_dash")
func _begin_thrust() -> void:
	## 向前戳击的动作：没有专门的戳刺动捕，用"斩击加速 + 骨架整体前探"凑出人随剑走的突刺感。
	## _hit_emitted 先置真：这一下的伤害走 player 的路径扫过判定，动画本身不发命中信号。
	if _attacking or _anim_player == null:
		return
	_attacking = true
	_hit_emitted = true
	_skill_swing = false
	_gain_scale = 1.0
	_thrust_anim = SKILL2_ANIM_T
	_hist.clear()
	_anim_player.play(SLASH_ANIM, -1.0, SKILL2_SPEED)
	SFX.play("swing", SKILL2_SFX_DB)
	action.emit("thrust")
func _begin_swing(heavy: bool) -> void:
	## 起一剑：heavy=false 普通戳击；true=技能「劈砍」——幅度更大、更慢、更响、金色剑气
	if _attacking or _anim_player == null:
		return
	_attacking = true
	_hit_emitted = false
	_skill_swing = heavy
	_gain_scale = SKILL_GAIN if heavy else 1.0
	_hist.clear()
	# play(动画, 混合, 速度)：劈砍放慢一点，看起来更沉、更用力
	_anim_player.play(SLASH_ANIM, -1.0, SKILL_SPEED if heavy else 1.0)
	SFX.play("swing", SKILL_SFX_DB if heavy else 0.0)
	_slash_fx(SKILL_FX_SCALE if heavy else 1.0,
		SKILL_FX_COLOR if heavy else Color(0.62, 0.80, 1.0))
	action.emit("heavy" if heavy else "slash")
func _slash_fx(scale := 1.0, col := Color(0.62, 0.80, 1.0)) -> void:
	## 剑气：立在相机前 1.15 米的一片斜月牙，朝向随视线水平方向
	## 挂在相机下（而不是场景根）：挥砍 0.3 秒内玩家照常跑动/落地，
	## 挂根节点会把弧光丢在原地、看起来"脱手"；跟视角走才像第一人称的挥击。
	var cam := get_parent() as Camera3D
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	SLAM_FX.spawn_slash(cam, cam.global_position + fwd * 0.95 + Vector3(0.0, -0.18, 0.0),
		fwd, 1.95 * scale, col)
# ---- 剑柄组件 ----
func _build_grip() -> void:
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.22, 0.13, 0.07)
	leather.roughness = 0.8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.75, 0.58, 0.25)
	brass.metallic = 0.8
	brass.roughness = 0.35
	var guard := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.17, 0.028, 0.035)
	guard.mesh = gm
	guard.material_override = brass
	guard.position = Vector3(0, 0, -0.075)
	guard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(guard)
	var grip := MeshInstance3D.new()
	var cgm := CylinderMesh.new()
	cgm.top_radius = 0.019
	cgm.bottom_radius = 0.021
	cgm.height = 0.17
	grip.mesh = cgm
	grip.material_override = leather
	grip.position = Vector3(0, 0, 0.03)
	grip.rotation_degrees = Vector3(90, 0, 0)
	grip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grip)
	var pommel := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.028
	pm.height = 0.056
	pommel.mesh = pm
	pommel.material_override = brass
	pommel.position = Vector3(0, 0, 0.12)
	pommel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pommel)
# ---- 剑刃组件（沿 -Z 前向） ----
func _build_blade() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.80, 0.85)
	steel.metallic = 0.9
	steel.roughness = 0.22
	var fuller_mat := StandardMaterial3D.new()
	fuller_mat.albedo_color = Color(0.45, 0.47, 0.52)
	fuller_mat.metallic = 0.9
	fuller_mat.roughness = 0.4
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.014, 0.62)
	blade.mesh = bm
	blade.material_override = steel
	blade.position = Vector3(0, 0, -0.40)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blade)
	var fuller := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.016, 0.016, 0.50)
	fuller.mesh = fm
	fuller.material_override = fuller_mat
	fuller.position = Vector3(0, 0, -0.38)
	fuller.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fuller)
	var tip := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.05, 0.014, 0.09)
	tip.mesh = tm
	tip.material_override = steel
	tip.position = Vector3(0, 0, -0.74)
	tip.rotation_degrees = Vector3(0, 45, 0)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tip)
# ---- 残影（动态模糊）：挂在相机下（剑的父节点），按历史姿态显示 ----
func _build_trails() -> void:
	var parent := get_parent()
	for i in TRAIL_COUNT:
		var t := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.055, 0.02, 0.66)
		t.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.65, 0.78, 1.0, 0.30 - 0.08 * i)
		mat.emission_enabled = true
		mat.emission = Color(0.45, 0.62, 1.0)
		mat.emission_energy_multiplier = 1.5 - 0.4 * i
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		t.material_override = mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		parent.add_child.call_deferred(t)
		_trails.append(t)
func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		attack()
func is_active() -> bool:
	return active
func is_attacking() -> bool:
	## 挥砍动画是否还在放（从按 X 起手到动画结束）。
	## 这段时间 player 会拦住 C 切武器，和弓的"蓄力中不许切"是同一条规矩。
	return _attacking
func set_active(a: bool) -> void:
	active = a
	visible = a
	if not a:
		_attacking = false
		_skill_swing = false
		_gain_scale = 1.0
		_thrust_anim = 0.0
		for t in _trails:
			t.visible = false
		_hist.clear()
# ---- 对外：技能信息（HUD 状态行与蓄力条读这套，player 只管按 1 转发）----
func skill_name() -> String:
	return SKILL_NAME
func skill_cost() -> int:
	return SKILL_MP
func skill_cooldown() -> float:
	return SKILL_CD
func skill_cooldown_left() -> float:
	return _skill_cd
func skill_damage() -> int:
	## 劈砍伤害（1.6 × 当前攻击力，含强化）：问玩家要最终值，看到的=打出的
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("sword_skill_damage"):
		return int(p.call("sword_skill_damage"))
	return int(floor(50.0 * SWORD_SKILL_FALLBACK))
const SWORD_SKILL_FALLBACK := 1.6   # 玩家没就绪时的兜底倍率（跟 player.gd 的 SWORD_SKILL_MULT 同值）
func skill_desc() -> String:
	return "%d伤+定身1秒" % skill_damage()
func skill2_name() -> String:
	return SKILL2_NAME
func skill2_cost() -> int:
	return SKILL2_MP
func skill2_cooldown() -> float:
	return SKILL2_CD
func skill2_cooldown_left() -> float:
	return _skill2_cd
func skill2_desc() -> String:
	return "穿透80伤·流血10秒"
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
func _process(delta: float) -> void:
	if _skill_cd > 0.0:
		_skill_cd = maxf(0.0, _skill_cd - delta)   # 技能冷却不认手上没手上：切走了也照跳
	if _skill2_cd > 0.0:
		_skill2_cd = maxf(0.0, _skill2_cd - delta)
	if _hand_attach == null:
		return
	# 突刺前探：骨架整体往相机前方顶一下再收回（剑跟着手腕一起走，人剑一体）
	if _thrust_anim > 0.0:
		_thrust_anim = maxf(0.0, _thrust_anim - delta)
	var tk := 0.0
	if _thrust_anim > 0.0:
		tk = sin((1.0 - _thrust_anim / SKILL2_ANIM_T) * PI)
	_rig.position = RIG_POS + Vector3(0.0, -0.15, -0.5) * tk
	# 腕骨当前姿态（骨架局部）→ 相对待机的增量 → 增益放大 → 回到相机空间
	var cur_local: Transform3D = _rig.global_transform.affine_inverse() * _hand_attach.global_transform
	if _has_ref:
		# 位移：绕待机手位放大；旋转：增量转成轴角，角度乘增益（带上限）后叠加基准
		var rp := _ref_local.origin
		var new_pos := rp + (cur_local.origin - rp) * POS_GAIN * _gain_scale
		var cur_b := _norm_basis(cur_local.basis)
		var d := Transform3D(cur_b * _ref_local.basis.inverse(), Vector3.ZERO)
		var q := d.basis.get_rotation_quaternion()
		var half := acos(clampf(absf(q.w), 0.0, 1.0))
		var ang := half * 2.0
		var new_basis: Basis
		if ang < 0.001:
			new_basis = _ref_local.basis
		else:
			var ax := (Vector3(q.x, q.y, q.z) / sin(half)).normalized()
			new_basis = Basis(ax, minf(ang * ROT_GAIN * _gain_scale, 3.0 * _gain_scale)) * _ref_local.basis
		cur_local = Transform3D(new_basis, new_pos)
	var hb := cur_local.basis
	hb = Basis(hb.x.normalized(), hb.y.normalized(), hb.z.normalized())
	global_transform = Transform3D(hb, cur_local.origin) * HAND_CORRECTION
	global_transform = _rig.global_transform * global_transform
	if _attacking:
		_record_and_draw_trails(delta)
		_check_hit_timing()
func _check_hit_timing() -> void:
	if _hit_emitted or _anim_player == null:
		return
	var cur := _anim_player.current_animation
	if cur != SLASH_ANIM:
		return
	var anim: Animation = _anim_player.get_animation(SLASH_ANIM)
	if anim == null:
		return
	if _anim_player.get_current_animation_position() >= anim.length * 0.35:
		_hit_emitted = true
		if _skill_swing:
			skill_hit.emit()      # 劈砍：player 结算 1.6 倍伤害 + 定身 1 秒
		else:
			slash_hit.emit()
func _record_and_draw_trails(delta: float) -> void:
	# 记录剑相对相机的局部姿态（视角旋转不影响残影贴合）
	_hist.push_front(transform)
	if _hist.size() > 60:
		_hist.resize(60)
	var fps_mult: float = maxf(1.0, 1.0 / maxf(delta, 0.0005))
	for i in TRAIL_COUNT:
		var lag_frames: int = int(round(float(i + 1) * TRAIL_DELAY * fps_mult))
		lag_frames = clampi(lag_frames, 1, _hist.size() - 1)
		var tr: Transform3D = _hist[lag_frames]
		# 残影中心对齐刃身中点（刃相对剑柄 -0.31~-0.40）
		_trails[i].transform = Transform3D(tr.basis, tr.origin + tr.basis * Vector3(0, 0, -0.36))
		_trails[i].visible = true
func _find_node(n: Node, cls: String) -> Node:
	for c in n.get_children():
		if c.get_class() == cls:
			return c
		var r := _find_node(c, cls)
		if r != null:
			return r
	return null
func _find_nodes(n: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		if c.get_class() == cls:
			out.append(c)
		out.append_array(_find_nodes(c, cls))
	return out
