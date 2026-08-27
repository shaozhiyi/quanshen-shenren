extends CharacterBody3D
## 第一人称行走控制：WASD 移动、鼠标转视角、空格跳跃、ESC/点击切换鼠标捕获。
## 附带 HP 系统：take_damage()/heal() + hp_changed/died 信号，供后续战斗/交互使用。

@export var move_speed := 5.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0022
@export var max_hp := 100.0

signal hp_changed(current: float, maximum: float)
signal died

var hp := 100.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_pos := Vector3(0.0, 5.0, 0.0)
var _sword: Node
var _bow: Node
var _weapon := 0        # 0=主武器剑 1=副武器弓
var _has := [true, true]  # 装备栏：[剑, 弓] 是否已装备
var armor_factor := 1.0   # 护甲减伤系数（穿上防具=0.5，光环伤害减半）
var _invincible := false
var _invincible_t := 0.0
var _invincible_dur := 0.0
signal invincibility_changed(active: bool, duration: float)
var _inv: Node            # 背包/装备覆盖层（HUD/Inventory）
var _hud: Node            # HUD 画布层（屏幕 toast 提示）
var _boss: Node
var _arena: Node
var _in_arena := false
var _saved_pos := Vector3.ZERO
var _saved_yaw := 0.0
var _saved_pitch := 0.0
var _saved_env: Environment
const BOSS_INTERACT_DIST := 12.0

# 冲刺：连续（双击）同一方向键触发一小段爆发位移
const DOUBLE_TAP_WINDOW := 0.28   # 两次点按间隔小于此值判定为双击
const DASH_SPEED := 18.0          # 冲刺瞬时速度（约 3.6× 步行）
const DASH_DURATION := 0.2        # 冲刺持续
const DASH_COOLDOWN := 0.5        # 冲刺后摇冷却，防连发
var _dash_time := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _last_tap := {}               # action -> 上次点按时刻(秒)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hp = max_hp
	connect("died", _on_died)
	_boss = get_node_or_null("../Boss")
	_spawn_pos = _find_spawn()
	global_position = _spawn_pos
	# 本局地形随机后，让 BOSS 在出生点附近的环形带里另挑一处平缓落点
	if _boss != null and _boss.has_method("place_near"):
		_boss.call("place_near", _spawn_pos, get_node_or_null("../Ground"))
	if _boss != null:
		_boss.connect("died", _on_boss_died)
	_sword = get_node_or_null("Camera3D/Sword")
	if _sword != null:
		_sword.connect("slash_hit", _on_slash_hit)
	_bow = get_node_or_null("Camera3D/Bow")
	if _bow != null:
		_bow.set_active(false)
	_arena = get_node_or_null("../Arena")
	_inv = get_node_or_null("../HUD/Inventory")
	_hud = get_node_or_null("../HUD")


func in_arena() -> bool:
	return _in_arena


func near_boss() -> bool:
	## 大地图上靠近存活 BOSS 且未持弓蓄力时，HUD 显示按 E 提示
	if _in_arena or _boss == null or _boss.is_dead():
		return false
	return global_position.distance_to(_boss.global_position) <= BOSS_INTERACT_DIST


func _try_interact_boss() -> void:
	if _in_arena:
		_exit_arena()
	elif near_boss():
		_enter_arena()


func _enter_arena() -> void:
	## 进入 BOSS 空间：隐藏大地图视觉，切到超平坦白色空间，BOSS 传送就位
	_saved_pos = global_position
	_saved_yaw = rotation.y
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		_saved_pitch = cam.rotation.x
	for npath in ["../Ground", "../GroundDetails", "../SkyDome", "../Sun"]:
		var nd := get_node_or_null(npath)
		if nd != null:
			nd.visible = false
	var owe := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if owe != null:
		_saved_env = owe.environment
		owe.environment = _arena.arena_env
	_arena.set_active(true)
	var center: Vector3 = _arena.ARENA_CENTER
	_boss.teleport_to(center + Vector3(0, 0, -10))
	_boss.set_arena_mode(true)
	global_position = center + Vector3(0, 1.05, 6)
	velocity = Vector3.ZERO
	rotation.y = 0.0
	if cam != null:
		cam.rotation.x = 0.0
	_in_arena = true


func _exit_arena() -> void:
	## 离开 BOSS 空间：恢复大地图与 BOSS 原位、玩家位姿
	_in_arena = false
	if _boss != null:
		_boss.set_arena_mode(false)
		_boss.go_home()
	if _arena != null:
		_arena.set_active(false)
	for npath in ["../Ground", "../GroundDetails", "../SkyDome", "../Sun"]:
		var nd := get_node_or_null(npath)
		if nd != null:
			nd.visible = true
	var owe := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if owe != null and _saved_env != null:
		owe.environment = _saved_env
	global_position = _saved_pos
	rotation.y = _saved_yaw
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.rotation.x = _saved_pitch


func _on_boss_died() -> void:
	## BOSS 在空间中被击败：按难度发放野生狗奶，等沉地动画播完后自动送回大地图（BOSS 复活）
	var n := 2
	var dname := "普通"
	if _boss != null:
		n = int(_boss.call("reward_count"))
		dname = String(_boss.call("difficulty_name"))
	if _inv != null and _inv.has_method("add_item"):
		if _inv.call("add_item", "dogmilk", n):
			_toast("缴获野生狗奶 ×%d（%s难度）" % [n, dname])
		else:
			_toast("背包已满，野生狗奶未能全部收走")
	if not _in_arena:
		return
	get_tree().create_timer(3.0).timeout.connect(_exit_arena)


func _try_cycle_difficulty() -> void:
	## 大地图上靠近 BOSS 时按 R：切到下一档挑战难度（击败过一次后解锁）
	if _boss == null or _in_arena or not near_boss():
		return
	if not _boss.call("can_adjust_difficulty"):
		_toast("先击败野生狗奶一次，才能调节难度")
		return
	_boss.call("cycle_difficulty")
	var hp_max := int(_boss.get("max_hp"))
	var mult: float = float(_boss.call("aura_damage")) / 0.3
	_toast("难度 %s ｜ HP %d ｜ 光环伤害 ×%.1f ｜ 掉落 ×%d" % [
		String(_boss.call("difficulty_name")), hp_max, mult, int(_boss.call("reward_count"))])


func _toast(text: String) -> void:
	## 屏幕中下方短暂提示（HUD 就绪则用 HUD 的 toast，否则退回背包面板提示）
	if _hud != null and _hud.has_method("toast"):
		_hud.call("toast", text)
	elif _inv != null and _inv.has_method("flash_hint"):
		_inv.call("flash_hint", text)


func _on_died() -> void:
	## 血量归零：以 30% 血苏醒；在 BOSS 空间内则视为挑战失败被弹出（BOSS 下次仍满血）
	hp = max_hp * 0.3
	hp_changed.emit(hp, max_hp)
	if _in_arena:
		_exit_arena()
		_toast("不敌野生狗奶……被送出空间（下次挑战 BOSS 满血）")
	else:
		_toast("我倒下了……")


func _try_pick_box() -> bool:
	## 附近有掉落箱则回收其物品到背包并销毁箱子；返回是否处理了箱子
	if _inv == null or not _inv.has_method("add_item"):
		return false
	var box := _nearest_box()
	if box == null:
		return false
	if not _inv.call("add_item", String(box.item_id)):
		_toast("背包已满，无法回收 " + String(_inv.item_name(box.item_id)))
		return true
	box.queue_free()
	_toast("已回收 " + String(_inv.item_name(box.item_id)))
	return true


func _nearest_box() -> Node:
	var best: Node = null
	var best_d := 3.5
	for b in get_tree().get_nodes_in_group("drop_box"):
		if not is_instance_valid(b):
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func spawn_drop_box(item_id: String) -> void:
	## 在玩家身前生成一个掉落箱（Area3D + 箱子图标），承载被丢弃的物品
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	var box: Area3D = load("res://scripts/drop_box.gd").new()
	box.name = "DropBox"
	scene.add_child(box)
	box.setup(item_id)
	var f := -global_transform.basis.z
	var pos := global_position + f * 1.6
	var ground := get_node_or_null("../Ground")
	if _in_arena or ground == null or not ground.has_method("height_at_fast"):
		pos.y = global_position.y - 0.6
	else:
		pos.y = ground.height_at_fast(pos.x, pos.z) + 0.5
	box.global_position = pos


func _switch_weapon() -> void:
	## Z 键：主/副武器切换（剑 ↔ 弓）；仅当两把都已装备时可切
	if _has[0] and _has[1]:
		_equip(1 - _weapon)


func _equip(w: int) -> void:
	## 激活指定武器视图（0=剑 1=弓）
	_weapon = w
	if _sword != null:
		_sword.set_active(w == 0)
	if _bow != null:
		_bow.set_active(w == 1)


func set_equipment(weapon_id: String, sub_id: String, armor_id: String) -> void:
	## 由背包/装备栏调用：同步已装备状态与护甲减伤；当前武器被卸下则自动改用另一把
	_has[0] = (weapon_id == "sword")
	_has[1] = (sub_id == "bow")
	armor_factor = 0.5 if armor_id != "" else 1.0
	if _has[_weapon]:
		_equip(_weapon)
	else:
		var found := false
		for w in 2:
			if _has[w]:
				_equip(w)
				found = true
				break
		if not found:
			if _sword != null:
				_sword.set_active(false)
			if _bow != null:
				_bow.set_active(false)


func _on_slash_hit() -> void:
	## 挥砍中段向前射线，命中 boss 扣血（BOSS 暂不反击）
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 4.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1   # 只看世界/BOSS（箭在层2，不挡剑）
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col: Node = hit.collider
		if col.is_in_group("boss"):
			var boss := col.get_parent()
			if boss.has_method("take_damage"):
				boss.take_damage(50)


func _find_spawn() -> Vector3:
	## 在原点附近找一处小山顶作为出生点，避免开局掉进地形低洼处
	var ground := get_node_or_null("../Ground")
	if ground == null or not ground.has_method("height_at"):
		return Vector3(0.0, 5.0, 0.0)
	var best := Vector3(0.0, ground.height_at(0.0, 0.0) + 2.0, 0.0)
	var best_h: float = ground.height_at(0.0, 0.0)
	var radii: Array[float] = [15.0, 30.0, 45.0]
	for rv in radii:
		var r: float = rv
		for i in 12:
			var ang := TAU * float(i) / 12.0
			var x := cos(ang) * r
			var z := sin(ang) * r
			var h: float = ground.height_at(x, z)
			if h > best_h:
				best_h = h
				best = Vector3(x, h + 2.0, z)
	return best


func take_damage(amount: float) -> void:
	## 受到伤害：按护甲减伤系数扣血并发出 hp_changed，血量归零时发出 died（支持小数伤害）
	if amount <= 0.0 or _invincible:
		return
	hp = clampf(hp - amount * armor_factor, 0.0, max_hp)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		died.emit()


func gain_invincibility(dur: float) -> void:
	## 饮用野生狗奶：dur 秒无敌（免疫伤害），HUD 血条常显；到时解除并恢复满血
	_invincible = true
	_invincible_dur = dur
	_invincible_t = dur
	invincibility_changed.emit(true, dur)


func is_invincible() -> bool:
	return _invincible


func _end_invincibility() -> void:
	_invincible = false
	_invincible_t = 0.0
	invincibility_changed.emit(false, 0.0)
	heal(max_hp)   # 解除时恢复满血


func heal(amount: float) -> void:
	## 治疗：回血并发出 hp_changed
	if amount <= 0.0 or hp >= max_hp:
		return
	hp = clampf(hp + amount, 0.0, max_hp)
	hp_changed.emit(hp, max_hp)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# 水平：绕 Y 轴旋转身体；垂直：仅旋转相机并限制角度
		rotate_y(-event.relative.x * mouse_sensitivity)
		$Camera3D.rotate_x(-event.relative.y * mouse_sensitivity)
		$Camera3D.rotation.x = clampf($Camera3D.rotation.x, -1.5, 1.5)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ui_cancel"):
			# ESC：在捕获与释放之间切换
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.keycode == KEY_Z:
			# Z：主/副武器切换（剑 ↔ 弓）
			_switch_weapon()
		elif event.keycode == KEY_E:
			# E：附近有掉落箱→回收；否则靠近 BOSS 进入其空间 / 空间内离开
			if not _try_pick_box():
				_try_interact_boss()
		elif event.keycode == KEY_R:
			# R：靠近 BOSS 时切换下一档挑战难度（击败过一次后解锁）
			_try_cycle_difficulty()


func _physics_process(delta: float) -> void:
	# 无敌倒计时：结束即恢复满血
	if _invincible:
		_invincible_t -= delta
		if _invincible_t <= 0.0:
			_end_invincibility()
	# 掉出世界的保险
	if _in_arena:
		# BOSS 空间：掉出超平坦地板下方则回到空间中心
		if global_position.y < _arena.ARENA_CENTER.y - 20.0:
			global_position = _arena.ARENA_CENTER + Vector3(0, 1.05, 4)
			velocity = Vector3.ZERO
	elif global_position.y < -20.0:
		global_position = _spawn_pos
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# 双击方向键 → 冲刺：检测同一移动键在时间窗内被再次点按
	var now := Time.get_ticks_msec() / 1000.0
	for act in ["move_forward", "move_back", "move_left", "move_right"]:
		if Input.is_action_just_pressed(act):
			var prev: float = _last_tap.get(act, -99.0)
			if now - prev <= DOUBLE_TAP_WINDOW and _dash_cd <= 0.0 and _dash_time <= 0.0:
				_start_dash(act)
			_last_tap[act] = now

	if _dash_time > 0.0:
		# 冲刺中：覆盖水平速度
		_dash_time -= delta
		velocity.x = _dash_dir.x * DASH_SPEED
		velocity.z = _dash_dir.z * DASH_SPEED
	else:
		# 获取移动输入（x: 左右, y: 前后），并按身体朝向转为世界方向
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		if direction:
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, move_speed)
			velocity.z = move_toward(velocity.z, 0.0, move_speed)

	if _dash_cd > 0.0:
		_dash_cd -= delta

	move_and_slide()


func _start_dash(act: String) -> void:
	## 依据被双击的方向键，沿身体朝向的对应水平方向发起一段冲刺
	var d := Vector3.ZERO
	match act:
		"move_forward": d = -transform.basis.z
		"move_back":    d = transform.basis.z
		"move_left":    d = -transform.basis.x
		"move_right":   d = transform.basis.x
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return
	_dash_dir = d.normalized()
	_dash_time = DASH_DURATION
	_dash_cd = DASH_COOLDOWN
