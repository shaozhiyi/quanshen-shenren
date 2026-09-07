extends CharacterBody3D
class_name PvpPlayer
## 局域网 PVP 的玩家：移动/武器/技能与单机同一套（武器脚本直接复用），
## 区别在于——700 血、伤害由房主结算（本机只把"我打中了谁"报给房主）、
## 远程玩家的本体只做位置插值 + 头顶名牌血条。
## 节点约定：所有玩家都挂在竞技场 root/Players/P<peer_id> 下，两边的路径完全一致，
## RPC 才能对上；本机自己的那只在 group "local_player" 里（背包靠它找我）。

signal hp_changed(current: float, maximum: float)
signal died_signal(killer_id: int)

@export var mouse_sensitivity := 0.0022
@export var move_speed := 5.0
@export var jump_velocity := 4.5

const MAX_AIR_JUMPS := 1
const AIR_JUMP_MULT := 0.92
const RUN_MULT := 2.0
const DASH_SPEED := 18.0
const DASH_DURATION := 0.2
const DASH_COOLDOWN := 0.5

# ---- 强化（与单机同一套指数算法，双击装备吃强化石）----
const ENHANCE_MAX := 10
const ENH_GROWTH := 1.10
const ENHANCE_KINDS := ["sword", "bow", "armor", "staff"]
const SWORD_DMG := 50.0
const SWORD_SKILL_MULT := 1.6
const SWORD_SKILL_STUN := 1.0
var enhance_levels := {"sword": 0, "bow": 0, "armor": 0, "staff": 0}

# ---- 魔法（技能消耗）----
@export var max_mp := 200.0
const MP_REGEN_PER_SEC := 2.0
var mp := 200.0
var _mp_regen_acc := 0.0
signal mp_changed(current: float, maximum: float)

# ---- PVP 血量与身份 ----
var pvp_id := 1                   # = ENet peer id（房主=1）
var display_name := "玩家1"
var max_hp := PvpState.MAX_HP
var hp := PvpState.MAX_HP
var kills := 0
var dead := false
var _invincible_t := 0.0          # 狗奶无敌（本机表现；房主也有倒计时做结算）
signal invincibility_changed(active: bool, duration: float)

# ---- 移动 ----
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _air_jumps := 0
var _running := false
var _last_tap := {}               # 方向键双击计时（进奔跑）
var _dash_time := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _slow_t := 0.0                # PVP 暂无减速来源，留接口

# ---- 突刺（与单机同一套参数，扫到的目标走 take_damage 上报房主）----
const THRUST_DIST := 6.0
const THRUST_SPEED := 34.0
const THRUST_EXTRA_MAX := 4.0
const THRUST_DMG := 80
const THRUST_BLEED_MULT := 0.9
const THRUST_BLEED_T := 10.0
const THRUST_HIT_R := 2.8
var _thrust_left := 0.0
var _thrust_dir := Vector3.ZERO
var _thrust_hit: Array = []
var _stun_t := 0.0                # 被劈砍定身：几秒内不能动（房主广播给本人执行）

# ---- 武器 ----
var _weapon := 0                  # 0=剑 1=弓 2=法杖（与 WEAPON_IDS 同下标）
var _has := [true, true, false]   # 三把武器谁在身上（两格装备栏，最多两把为真）
var _sword: Node
var _bow: Node
var _staff: Node
const WEAPON_IDS := ["sword", "bow", "staff"]

# ---- 网络插值 ----
var _net_target := Vector3.ZERO
var _net_yaw := 0.0
var _net_send_accum := 0.0
var _spawn_point := Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	add_to_group("pvp_target")
	_build_view()
	if not is_multiplayer_authority():
		# 远程玩家：收起第一人称视角模型，摆出第三人称小盒子
		$Camera3D.current = false
		_set_viewmodel_visible(false)
		$Avatar.visible = true
	else:
		add_to_group("local_player")
		$Avatar.visible = false
	$Avatar/Name.text = display_name


func _set_viewmodel_visible(v: bool) -> void:
	for w in [$Camera3D/Sword, $Camera3D/Bow, $Camera3D/Staff]:
		if w != null:
			w.visible = v


## 组装视角（相机 + 三把武器）与第三人称外观；必须在 add_child 之前调用
func setup(id: int, nm: String, spawn_pos: Vector3) -> void:
	pvp_id = id
	display_name = nm
	name = "P%d" % id
	position = spawn_pos
	_spawn_point = spawn_pos
	_net_target = spawn_pos
	set_multiplayer_authority(id)


func _build_view() -> void:
	var cap := CollisionShape3D.new()
	cap.name = "Col"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	cap.shape = shape
	cap.position = Vector3(0, 0.85, 0)
	add_child(cap)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 1.6, 0)
	cam.fov = 75.0
	add_child(cam)

	# 三把武器：与 main.tscn 相同的挂法（武器脚本自己建模型、自己收输入）
	_sword = Node3D.new()
	_sword.name = "Sword"
	_sword.set_script(load("res://scripts/sword.gd"))
	cam.add_child(_sword)
	_bow = Node3D.new()
	_bow.name = "Bow"
	_bow.set_script(load("res://scripts/bow.gd"))
	cam.add_child(_bow)
	_staff = Node3D.new()
	_staff.name = "Staff"
	_staff.set_script(load("res://scripts/staff.gd"))
	cam.add_child(_staff)
	_sword.connect("slash_hit", _on_slash_hit)
	_sword.connect("skill_hit", _on_skill_hit)
	_equip(0)

	# 第三人称外观：颜色块 + 名牌 + 血条（远程玩家看到的样子）
	var avatar := Node3D.new()
	avatar.name = "Avatar"
	add_child(avatar)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 1.7, 0.9)
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.55 + 0.1 * float(pvp_id % 4), 0.3 + 0.15 * float(pvp_id % 3))
	mat.roughness = 0.7
	body.material_override = mat
	body.position = Vector3(0, 0.85, 0)
	avatar.add_child(body)
	var name_tag := Label3D.new()
	name_tag.name = "Name"
	name_tag.text = display_name
	name_tag.position = Vector3(0, 2.45, 0)
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.font_size = 40
	name_tag.pixel_size = 0.004
	name_tag.modulate = Color(1, 0.95, 0.7)
	avatar.add_child(name_tag)
	var hp_tag := Label3D.new()
	hp_tag.name = "Hp"
	hp_tag.position = Vector3(0, 2.15, 0)
	hp_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_tag.font_size = 34
	hp_tag.pixel_size = 0.004
	hp_tag.modulate = Color(0.6, 1.0, 0.6)
	avatar.add_child(hp_tag)
	_refresh_hp_tag()


func _refresh_hp_tag() -> void:
	var tag := get_node_or_null("Avatar/Hp")
	if tag != null:
		tag.text = "%d / %d" % [int(hp), int(max_hp)]


# ---- 伤害：本机永远只"上报"，结算在房主（见 pvp_arena.rpc_claim_hit）----
func take_damage(amount: int, weapon := "") -> void:
	if dead or not is_inside_tree():
		return
	var arena := _arena_node()
	if arena == null:
		return
	# 跑到这段代码的机器 = 射手的机器（弹体只在射手那儿存在），攻击者就是本机玩家
	if multiplayer.is_server():
		arena.call("settle_hit", pvp_id, amount, weapon, 1)
	else:
		arena.rpc_id(1, "rpc_claim_hit", pvp_id, amount, weapon)


## 房主结算后的结果广播到每个人（含本人）：改的是本地显示值，生杀大权在房主
func apply_hp(v: float) -> void:
	hp = clampf(v, 0.0, max_hp)
	hp_changed.emit(hp, max_hp)
	_refresh_hp_tag()


func is_dead() -> bool:
	return dead


func set_dead(v: bool) -> void:
	dead = v
	visible = not dead
	set_process(not v)
	set_physics_process(not v)
	$Col.set_deferred("disabled", v)
	if dead:
		_set_viewmodel_visible(false)
		$Avatar.visible = false
	else:
		position = _spawn_point
		_net_target = _spawn_point
		if is_multiplayer_authority():
			_set_viewmodel_visible(true)
			$Camera3D.current = true
		else:
			$Avatar.visible = true


## 狗奶：10 秒无敌（免疫伤害），本机表现 + 房主记账结算
func gain_invincibility(dur: float) -> void:
	_invincible_t = maxf(_invincible_t, dur)
	invincibility_changed.emit(true, _invincible_t)
	var arena := _arena_node()
	if arena != null:
		if multiplayer.is_server():
			arena.call("notify_invincible", pvp_id, _invincible_t)
		else:
			arena.rpc_id(1, "rpc_notify_invincible", pvp_id, _invincible_t)


func is_invincible() -> bool:
	return _invincible_t > 0.0


func _arena_node() -> Node:
	return get_tree().current_scene if is_inside_tree() else null


# ---- 强化（与单机同一套指数算法）----
func damage_scale_for(id: String) -> float:
	return pow(ENH_GROWTH, float(enhance_level_of(id)))


func attack_power(id: String, base: float) -> int:
	return int(floor(base * damage_scale_for(id)))


func sword_damage() -> int:
	return attack_power("sword", SWORD_DMG)


func sword_skill_damage() -> int:
	return int(floor(float(sword_damage()) * SWORD_SKILL_MULT))


func enhance_max() -> int:
	return ENHANCE_MAX


func enhance_level_of(id: String) -> int:
	return int(enhance_levels.get(id, 0))


func enhance_item(id: String) -> bool:
	if not ENHANCE_KINDS.has(id):
		return false
	var lv := enhance_level_of(id)
	if lv >= ENHANCE_MAX:
		return false
	enhance_levels[id] = lv + 1
	return true


# ---- 魔法 ----
func has_mp(amount: float) -> bool:
	return mp >= amount


func spend_mp(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if mp < amount:
		return false
	mp = clampf(mp - amount, 0.0, max_mp)
	mp_changed.emit(mp, max_mp)
	return true


func restore_mp(amount: float) -> void:
	if amount <= 0.0 or mp >= max_mp:
		return
	mp = clampf(mp + amount, 0.0, max_mp)
	mp_changed.emit(mp, max_mp)


# ---- 武器在身上（两格装备栏：武器/副武器；法杖可以占任意一格）----
func set_equipment(weapon_id: String, sub_id: String, armor_id: String, staff_id: String = "") -> void:
	var ids := [weapon_id, sub_id, staff_id]
	for i in WEAPON_IDS.size():
		_has[i] = ids.has(WEAPON_IDS[i])
	if _weapon < _has.size() and _has[_weapon]:
		_equip(_weapon)
		return
	for w in _has.size():
		if _has[w]:
			_equip(w)
			return
	_equip(-1)


func weapon_id_at(i: int) -> String:
	if i >= 0 and i < WEAPON_IDS.size():
		return WEAPON_IDS[i]
	return ""


func current_weapon_id() -> String:
	return weapon_id_at(_weapon)


func is_equipped(i: int) -> bool:
	return i >= 0 and i < _has.size() and _has[i]


func set_current_weapon(w: int) -> void:
	if w >= 0 and w < _has.size() and _has[w]:
		_equip(w)


func equipped_count() -> int:
	var n := 0
	for h in _has:
		if h:
			n += 1
	return n


func next_weapon_index() -> int:
	var total := _has.size()
	for step in range(1, total + 1):
		var i := (_weapon + step) % total
		if _has[i]:
			return i
	return _weapon


func _switch_weapon() -> void:
	if equipped_count() < 2 or weapon_busy():
		return
	_equip(next_weapon_index())


func _equip(w: int) -> void:
	_weapon = w
	if _sword != null:
		_sword.set_active(w == 0)
	if _bow != null:
		_bow.set_active(w == 1)
	if _staff != null:
		_staff.set_active(w == 2)


func weapon_busy() -> bool:
	if _weapon == 1 and _bow != null and _bow.has_method("is_charging"):
		return bool(_bow.call("is_charging"))
	if _weapon == 2 and _staff != null:
		if _staff.has_method("is_charging") and bool(_staff.call("is_charging")):
			return true
		if _staff.has_method("is_attacking") and bool(_staff.call("is_attacking")):
			return true
		if _staff.has_method("cooldown_left") and float(_staff.call("cooldown_left")) > 0.0:
			return true
	if _weapon == 0 and _sword != null and _sword.has_method("is_attacking"):
		return bool(_sword.call("is_attacking"))
	return false


## 被劈砍定身：本人上报房主（结算权在房主），房主再广播给本人执行
func stun(sec: float, _stack := false) -> void:
	if dead or sec <= 0.0:
		return
	var arena := _arena_node()
	if arena == null:
		return
	if multiplayer.is_server():
		arena.call("settle_stun", pvp_id, sec)
	else:
		arena.rpc_id(1, "rpc_claim_stun", pvp_id, sec)


## 房主广播给本人的执行：几秒内不能动（被打断不了技能，只冻移动）
func apply_stun(sec: float) -> void:
	_stun_t = maxf(_stun_t, sec)


# ---- 突刺（由 sword.gd 的 skill2_hold 起手）----
func thrust_dash() -> void:
	var cam := get_node_or_null("Camera3D") as Camera3D
	var f := -transform.basis.z
	if cam != null:
		f = -cam.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		f = -transform.basis.z
	_thrust_dir = f.normalized()
	_thrust_left = _plan_thrust_distance(THRUST_DIST)
	_thrust_hit.clear()
	velocity.x *= 0.2
	velocity.z *= 0.2


func _plan_thrust_distance(base: float) -> float:
	## 先看路：射线跳过其他玩家找第一面墙；终点还卡在别人身体里就往前顺
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.9, 0)
	var wall_d := base
	var skip := 0.0
	for i in 6:
		var q := PhysicsRayQueryParameters3D.create(from + _thrust_dir * skip,
			from + _thrust_dir * (base + 1.0))
		q.collision_mask = 1
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var n: Node = hit.collider
		while n != null and not (n is PvpPlayer):
			n = n.get_parent()
		if n != null:
			skip = (hit.position - from).dot(_thrust_dir) + 0.6
			continue
		wall_d = clampf((hit.position - from).dot(_thrust_dir) - 0.7, 0.6, base)
		break
	var end_d := wall_d
	for i in 12:
		if not _point_in_other(from + _thrust_dir * (end_d + 0.4)):
			break
		end_d += 0.6
		if end_d >= base + THRUST_EXTRA_MAX:
			break
	return end_d


func _point_in_other(p: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group("pvp_target"):
		if n == self or not (n is PvpPlayer) or n.dead:
			continue
		var d: Vector3 = p - n.global_position
		if absf(d.y) < 2.2 and Vector2(d.x, d.z).length() < 0.9:
			return true
	return false


func _weapon_node() -> Node:
	match _weapon:
		0: return _sword
		1: return _bow
		2: return _staff
	return null


func _cast_skill() -> void:
	var w := _weapon_node()
	if w != null and w.has_method("cast_skill"):
		w.call("cast_skill")


func _cast_skill2(pressed: bool) -> void:
	var w := _weapon_node()
	if w == null or not w.has_method("skill2_hold"):
		return
	w.call("skill2_hold", pressed)


func bosses() -> Array:
	## 追踪箭等要的"目标列表"：其他玩家（不含自己）
	var out: Array = []
	for n in get_tree().get_nodes_in_group("pvp_target"):
		if n != self and n is PvpPlayer and not n.dead:
			out.append(n)
	return out


# ---- 命中判定（本机打的，目标节点上报房主）----
func _on_slash_hit() -> void:
	var t := _slash_ray_target()
	if t != null:
		t.take_damage(sword_damage(), "剑")


func _on_skill_hit() -> void:
	var t := _slash_ray_target()
	if t == null:
		return
	t.take_damage(sword_skill_damage(), "剑劈砍")
	if t.has_method("stun"):
		t.call("stun", SWORD_SKILL_STUN)


func _slash_ray_target() -> Node:
	## 挥砍射线：排除自己，打中别人的玩家节点就交上去
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return null
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 4.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var col: Node = hit.collider
	var n: Node = col
	while n != null and not (n is PvpPlayer):
		n = n.get_parent()
	if n != null and n != self:
		return n
	return null


# ---- 输入 ----
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		$Camera3D.rotate_x(-event.relative.y * mouse_sensitivity)
		$Camera3D.rotation.x = clampf($Camera3D.rotation.x, -1.5, 1.5)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and not event.echo:
		if event.pressed:
			if event.is_action_pressed("ui_cancel"):
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif event.keycode == KEY_Z:
				try_dash()
			elif event.keycode == KEY_C:
				_switch_weapon()
			elif event.keycode == KEY_1 or event.keycode == KEY_KP_1:
				_cast_skill()
			elif event.keycode == KEY_2 or event.keycode == KEY_KP_2:
				_cast_skill2(true)
		elif event.keycode == KEY_2 or event.keycode == KEY_KP_2:
			_cast_skill2(false)


func try_dash() -> bool:
	if _dash_cd > 0.0 or _dash_time > 0.0:
		return false
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var d := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	d.y = 0.0
	if d.length_squared() < 0.0001:
		d = -transform.basis.z
		d.y = 0.0
	if d.length_squared() < 0.0001:
		return false
	_dash_dir = d.normalized()
	_dash_time = DASH_DURATION
	_dash_cd = DASH_COOLDOWN
	return true


func try_jump() -> void:
	if is_on_floor():
		_air_jumps = MAX_AIR_JUMPS
		velocity.y = jump_velocity
	elif _air_jumps > 0:
		_air_jumps -= 1
		velocity.y = jump_velocity * AIR_JUMP_MULT


func speed_now() -> float:
	var spd := move_speed
	if _running:
		spd *= RUN_MULT
	if _slow_t > 0.0:
		spd *= 0.5
	return spd


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_net_interpolate(delta)
		return
	# 法力回复：每秒 2 点
	_mp_regen_acc += delta * 2.0
	if _mp_regen_acc >= 1.0:
		var pts := floorf(_mp_regen_acc)
		_mp_regen_acc -= pts
		restore_mp(pts)
	if _invincible_t > 0.0:
		_invincible_t = maxf(_invincible_t - delta, 0.0)
		if _invincible_t <= 0.0:
			invincibility_changed.emit(false, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		_air_jumps = MAX_AIR_JUMPS
	if Input.is_action_just_pressed("jump"):
		try_jump()
	# 双击同方向 → 奔跑
	var now := Time.get_ticks_msec() / 1000.0
	var holding := false
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		if Input.is_action_pressed(a):
			holding = true
			if Input.is_action_just_pressed(a):
				if now - float(_last_tap.get(a, -9.0)) < 0.3:
					_running = true
				_last_tap[a] = now
	if not holding:
		_running = false
	if _slow_t > 0.0:
		_slow_t = maxf(_slow_t - delta, 0.0)
	if _stun_t > 0.0:
		# 被劈砍定身：不能动也不能跳，攻击照常（与 BOSS 的"只控制不打断"同一口味）
		_stun_t = maxf(_stun_t - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_net_push(delta)
		return
	if _thrust_left > 0.0:
		var tstep: float = minf(_thrust_left, THRUST_SPEED * delta)
		global_position += _thrust_dir * tstep
		_thrust_left -= tstep
		_sweep_thrust_hits()
		velocity.x = 0.0
		velocity.z = 0.0
		if _thrust_left <= 0.0:
			_sweep_thrust_hits()
	elif _dash_time > 0.0:
		_dash_time -= delta
		velocity.x = _dash_dir.x * DASH_SPEED
		velocity.z = _dash_dir.z * DASH_SPEED
	else:
		var spd := speed_now()
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		if direction:
			velocity.x = direction.x * spd
			velocity.z = direction.z * spd
		else:
			velocity.x = move_toward(velocity.x, 0.0, spd)
			velocity.z = move_toward(velocity.z, 0.0, spd)
	if _dash_cd > 0.0:
		_dash_cd -= delta
	move_and_slide()
	# 位置广播：自己的机器说了算（每帧发，unreliable 省带宽）
	_net_push(delta)


func _net_push(delta: float) -> void:
	_net_send_accum += delta
	if _net_send_accum < 0.05:
		return
	_net_send_accum = 0.0
	for p in PvpState.players:
		var id := int(p.id)
		if id != pvp_id:
			net_pos.rpc_id(id, global_position, rotation.y)


## 房主给突刺穿透的目标结账：固定 80 + 流血（上报房主结算）
func _sweep_thrust_hits() -> void:
	for n in get_tree().get_nodes_in_group("pvp_target"):
		if n == self or not (n is PvpPlayer) or n.dead or n in _thrust_hit:
			continue
		var d: Vector3 = n.global_position - global_position
		if absf(d.y) < 3.4 and Vector2(d.x, d.z).length() < THRUST_HIT_R:
			_thrust_hit.append(n)
			n.take_damage(THRUST_DMG, "剑突刺")
			if n.has_method("bleed_from"):
				n.call("bleed_from", pvp_id, float(sword_damage()) * THRUST_BLEED_MULT, THRUST_BLEED_T)


## 突刺的流血：直接给房主上报"这笔持续伤害你来记"
func bleed_from(attacker_id: int, dps: float, seconds: float) -> void:
	var arena := _arena_node()
	if arena == null:
		return
	if multiplayer.is_server():
		arena.call("settle_bleed", pvp_id, attacker_id, dps, seconds)
	else:
		arena.rpc_id(1, "rpc_claim_bleed", pvp_id, attacker_id, dps, seconds)


# ---- 远程玩家：位置插值 ----
@rpc("authority", "call_remote", "unreliable_ordered")
func net_pos(pos: Vector3, yaw: float) -> void:
	_net_target = pos
	_net_yaw = yaw


func _net_interpolate(delta: float) -> void:
	global_position = global_position.lerp(_net_target, minf(1.0, delta * 14.0))
	rotation.y = lerp_angle(rotation.y, _net_yaw, minf(1.0, delta * 14.0))
