extends CharacterBody3D
## 第一人称行走控制：WASD 移动、鼠标转视角、空格跳跃、ESC/点击切换鼠标捕获。
## 附带 HP 系统：take_damage()/heal() + hp_changed/died 信号，供后续战斗/交互使用。

@export var move_speed := 5.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0022
@export var max_hp := 100.0

const SLAM_FX := preload("res://scripts/slam_fx.gd")
const MAX_AIR_JUMPS := 1        # 离地后还能再跳几次（1 = 二段跳）
const AIR_JUMP_MULT := 0.92     # 二段跳比地面起跳略弱

signal hp_changed(current: float, maximum: float)
signal died

var hp := 100.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_pos := Vector3(0.0, 5.0, 0.0)
var _sword: Node
var _bow: Node
var _weapon := 0        # 0=主武器剑 1=副武器弓
var _has := [true, true]  # 装备栏：[剑, 弓] 是否已装备
var armor_factor := 1.0   # 护甲减伤系数（穿上防具=0.7，即受到的伤害 ×0.7 后向下取整）
var _armor_on := false    # 当前是否穿着防具
const ENHANCE_MAX := 10                       # 每件装备各自封顶 +10
const ENHANCE_KINDS := ["sword", "bow", "armor"]  # 可强化对象（武器/装备，不含消耗品）
var enhance_levels := {"sword": 0, "bow": 0, "armor": 0}  # 逐件强化等级（双击该件→仅它+1）
var _dmg_carry := 0.0     # 防具取整后剩下的小数伤害，累计到下一次（否则 0.21/跳会被抹成 0）
var _invincible := false
var _invincible_t := 0.0
var _invincible_dur := 0.0
signal invincibility_changed(active: bool, duration: float)
var _inv: Node            # 背包/装备覆盖层（HUD/Inventory）
var _arena_boss: Node     # 当前正在交手的那只 BOSS
var _field: Node          # BossField：按名册生成多只 BOSS
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
var _air_jumps := 0               # 本次离地还能空中再跳几次
var _last_tap := {}               # action -> 上次点按时刻(秒)


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hp = max_hp
	connect("died", _on_died)
	_spawn_pos = _find_spawn()
	global_position = _spawn_pos
	_field = get_node_or_null("../BossField")
	if _field != null and _field.has_method("spawn_all"):
		_field.call("spawn_all", _spawn_pos)
	_arena = get_node_or_null("../Arena")
	_watch_bosses()
	_sword = get_node_or_null("Camera3D/Sword")
	if _sword != null:
		_sword.connect("slash_hit", _on_slash_hit)
	_bow = get_node_or_null("Camera3D/Bow")
	if _bow != null:
		_bow.set_active(false)
	_inv = get_node_or_null("../HUD/Inventory")
	_apply_loaded_state()


# ---- 存档：状态采集 / 套用 / F5 快速存档 ----
var kills := 0


func save_state() -> Dictionary:
	var cam := get_node_or_null("Camera3D") as Camera3D
	var pitch := 0.0
	if cam != null:
		pitch = cam.rotation.x
	return {
		"hp": hp, "max_hp": max_hp,
		"x": global_position.x, "y": global_position.y, "z": global_position.z,
		"yaw": rotation.y, "pitch": pitch, "weapon": _weapon, "kills": kills,
		"enhance": enhance_levels.duplicate(true),
		"invincible_left": _invincible_t if _invincible else 0.0,
	}


func _boss_states() -> Dictionary:
	var out := {}
	for b in bosses():
		var bd := {
			"difficulty": int(b.get("difficulty")),
			"beats": int(b.call("times_beaten")),
		}
		out[String(b.get("def_id"))] = bd
	return out


func _apply_loaded_state() -> void:
	## 读档进来时套用血量/位置/BOSS 进度；新游戏（pending_load 为空）什么都不做
	var d: Dictionary = SaveManager.pending_load
	if d.is_empty():
		return
	var p: Dictionary = d.get("player", {})
	if not p.is_empty():
		max_hp = float(p.get("max_hp", max_hp))
		hp = clampf(float(p.get("hp", max_hp)), 1.0, max_hp)
		hp_changed.emit(hp, max_hp)
		global_position = Vector3(float(p.get("x", global_position.x)),
			float(p.get("y", global_position.y)), float(p.get("z", global_position.z)))
		rotation.y = float(p.get("yaw", rotation.y))
		var cam := get_node_or_null("Camera3D") as Camera3D
		if cam != null:
			cam.rotation.x = float(p.get("pitch", 0.0))
		kills = int(p.get("kills", 0))
		_apply_enhance(p.get("enhance", 0))
		_refresh_armor_factor()
	var left := float(p.get("invincible_left", 0.0))
	if left > 0.0 and has_method("gain_invincibility"):
		gain_invincibility(left)
	var bs: Dictionary = d.get("bosses", {})
	for b in bosses():
		var id := String(b.get("def_id"))
		if bs.has(id):
			b.set("difficulty", int(bs[id].get("difficulty", 0)))
			b.set("_beats", int(bs[id].get("beats", 0)))
			b.call("apply_difficulty")   # 按还原的难度重算血量与光环


func set_current_weapon(w: int) -> void:
	## 读档时恢复"手上拿的是哪把"（装备状态由背包模块先同步）
	if (w == 0 or w == 1) and _has[w]:
		_equip(w)


func _quick_save() -> void:
	var path := SaveManager.current_slot
	if path == "":
		path = SaveManager.new_slot()
		SaveManager.current_slot = path
	var ground := get_node_or_null("../Ground")
	var seed_used := 0
	var amp := 0.0
	var freq := 0.0
	if ground != null:
		seed_used = int(ground.get("terrain_seed"))
		amp = float(ground.get("height_amp"))
		freq = float(ground.get("frequency"))
	var inv_state: Dictionary = {}
	if _inv != null and _inv.has_method("save_state"):
		inv_state = _inv.call("save_state")
	var data := SaveManager.build_data(seed_used, amp, freq, save_state(), inv_state, _boss_states(), kills)
	SaveManager.write_to(path, data)


# ---- 多 BOSS：按名册生成后，用"最近的那只"作为交互目标 ----
func bosses() -> Array:
	## 场上所有 BOSS 实体（"boss" 组只放碰撞体，供剑/箭射线命中判定）
	return get_tree().get_nodes_in_group("boss_unit")


func _watch_bosses() -> void:
	## 给场上每只 BOSS 的 died 信号连一次结算（新增 BOSS 后重复调用即可，不会重复连）
	for b in bosses():
		if b is Node and not b.is_connected("died", _on_boss_died):
			b.connect("died", _on_boss_died)


func nearest_boss() -> Node:
	## 大地图上离玩家最近且存活的 BOSS；超出交互半径则返回 null
	var best: Node = null
	var best_d := BOSS_INTERACT_DIST
	for b in bosses():
		if not (b is Node) or not is_instance_valid(b):
			continue
		if bool(b.call("is_dead")):
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d <= best_d:
			best_d = d
			best = b
	return best


func current_boss() -> Node:
	## HUD/交互统一入口：空间内用正在打的那只，大地图上用最近的存活 BOSS
	return _arena_boss if _in_arena else nearest_boss()


func in_arena() -> bool:
	return _in_arena


func near_boss() -> bool:
	## 大地图上靠近某只存活 BOSS 时，HUD 显示按 E 提示
	return not _in_arena and nearest_boss() != null


func _try_interact_boss() -> void:
	if _in_arena:
		_exit_arena()
	elif near_boss():
		_enter_arena()


func _enter_arena() -> void:
	## 进入 BOSS 空间：隐藏大地图视觉，切到超平坦白色空间，目标 BOSS 传送就位
	var b := nearest_boss()
	if b == null:
		return
	_arena_boss = b
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
	_arena_boss.teleport_to(center + Vector3(0, 0, -10))
	_arena_boss.set_arena_mode(true)
	global_position = center + Vector3(0, 1.05, 6)
	velocity = Vector3.ZERO
	rotation.y = 0.0
	if cam != null:
		cam.rotation.x = 0.0
	_in_arena = true


func _exit_arena() -> void:
	## 离开 BOSS 空间：恢复大地图与 BOSS 原位、玩家位姿
	_in_arena = false
	if _arena_boss != null and is_instance_valid(_arena_boss):
		_arena_boss.set_arena_mode(false)
		_arena_boss.go_home()
	_arena_boss = null
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


func _on_boss_died(b: Node = null) -> void:
	## 某只 BOSS 在空间中被击败：按它名册里的档位掉落发奖，沉地动画播完后自动回大地图
	if b == null or not is_instance_valid(b):
		b = _arena_boss
	if b == null:
		return
	kills += 1
	var item := String(b.call("get_reward_item"))
	var n := int(b.call("reward_count"))
	if _inv != null and _inv.has_method("add_item"):
		_inv.call("add_item", item, n)
		_inv.call("add_item", "stone", _roll_stones())
	if not _in_arena:
		return
	get_tree().create_timer(3.0).timeout.connect(_exit_arena)


const STONE_CHAIN_START := 0.80 * 0.05    # 追加掉落概率：原 80% 下调 5% → 4%
const STONE_CHAIN_STEP := 0.01 * 0.05     # 每成功一次概率递减量（原 1% → 0.05%）


func _roll_stones() -> int:
	## 必掉 1 块强化石；随后以 4%、3.95%、3.90%… 逐次递减追加，一旦失败即停
	## （概率整体调成原来的 5%，期望约 1.04 块/次击杀）
	var stones := 1
	var p := STONE_CHAIN_START
	while p > 0.0:
		if randf() < p:
			stones += 1
			p -= STONE_CHAIN_STEP
		else:
			break
	return stones


func _try_cycle_difficulty() -> void:
	## 大地图上靠近某只 BOSS 时按 R：切到下一档挑战难度（击败过一次后解锁）
	if _in_arena:
		return
	var b := nearest_boss()
	if b == null:
		return
	if not b.call("can_adjust_difficulty"):
		return
	b.call("cycle_difficulty")


func _on_died() -> void:
	## 血量归零：以 30% 血苏醒；在 BOSS 空间内则视为挑战失败被弹出（BOSS 下次仍满血）
	hp = max_hp * 0.3
	hp_changed.emit(hp, max_hp)
	if _in_arena:
		_exit_arena()


func _try_pick_box() -> bool:
	## 附近有掉落箱则回收其物品（含整堆数量）到背包并销毁箱子
	if _inv == null or not _inv.has_method("add_item"):
		return false
	var box := _nearest_box()
	if box == null:
		return false
	var n := int(box.get("item_count")) if box.get("item_count") != null else 1
	if not _inv.call("add_item", String(box.item_id), n):
		return true
	box.queue_free()
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


func spawn_drop_box(item_id: String, count: int = 1) -> void:
	## 在玩家身前生成一个掉落箱（Area3D + 箱子图标），承载被丢弃的物品（可整堆）
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	var box: Area3D = load("res://scripts/drop_box.gd").new()
	box.name = "DropBox"
	scene.add_child(box)
	box.setup(item_id, count)
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
	_armor_on = (armor_id != "")
	_refresh_armor_factor()
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


# ---- 装备强化（每件各自算级，消耗"装备强化石"） ----
func _refresh_armor_factor() -> void:
	## 穿甲基础 ×0.7，防具每级强化再减 3%（最低 0.4）；系数变化时清空取整余数
	var new_factor := 1.0
	if _armor_on:
		new_factor = clampf(0.7 - 0.03 * float(enhance_level_of("armor")), 0.4, 1.0)
	if new_factor != armor_factor:
		armor_factor = new_factor
		_dmg_carry = 0.0


func enhance_level_of(id: String) -> int:
	## 某件装备的强化等级（不可强化的物品恒为 0）
	return int(enhance_levels.get(id, 0))


func enhance_max() -> int:
	## 封顶等级（供背包面板显示；常量没法 call，这里包一层）
	return ENHANCE_MAX


func damage_scale_for(id: String) -> float:
	## 该武器的攻击力倍率：每级 +10%，只跟这件武器自己的等级有关
	return 1.0 + 0.10 * float(enhance_level_of(id))


func enhance_item(id: String) -> bool:
	## 双击某件武器/装备：只强化它自己，+1 级（最高 +10）。
	## 满级或物品不可强化返回 false —— 调用方（背包）据此不消耗强化石。
	if not ENHANCE_KINDS.has(id):
		return false
	var lv := enhance_level_of(id)
	if lv >= ENHANCE_MAX:
		return false
	enhance_levels[id] = lv + 1
	_refresh_armor_factor()
	return true


func _apply_enhance(data) -> void:
	## 读档套用强化等级：新存档是逐件字典，老存档是全身统一的整数（一律按当件等级还原）
	if typeof(data) == TYPE_DICTIONARY:
		for k in ENHANCE_KINDS:
			if data.has(k):
				enhance_levels[k] = clampi(int(data[k]), 0, ENHANCE_MAX)
	elif typeof(data) == TYPE_INT or typeof(data) == TYPE_FLOAT:
		var lv := clampi(int(data), 0, ENHANCE_MAX)
		for k in ENHANCE_KINDS:
			enhance_levels[k] = lv


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
				boss.take_damage(int(roundf(50.0 * damage_scale_for("sword"))))


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
	## 受到伤害并发出 hp_changed，血量归零时发出 died（支持小数伤害）
	## 穿防具：伤害 ×0.7 后向下取整；取整剩下的小数累积到下一次，
	## 否则 BOSS 光环 0.3/跳 ×0.7=0.21 会被取整成 0，等于完全免疫
	if amount <= 0.0 or _invincible:
		return
	var raw := amount * armor_factor
	var dealt := raw
	if armor_factor != 1.0:
		_dmg_carry += raw
		dealt = floorf(_dmg_carry)
		_dmg_carry -= dealt
	if dealt <= 0.0:
		return
	hp = clampf(hp - dealt, 0.0, max_hp)
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
		elif event.keycode == KEY_F5:
			# F5：写入 save/ 下的 JSON 存档
			_quick_save()


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

	if is_on_floor():
		_air_jumps = MAX_AIR_JUMPS      # 落地就补满空中跳数

	if Input.is_action_just_pressed("jump"):
		try_jump()

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


func air_jumps_left() -> int:
	return _air_jumps


func try_jump() -> int:
	## 0=跳不动 1=地面起跳 2=空中二段跳（落地补满次数，二段跳略弱并给一圈脚底光环）
	if is_on_floor():
		_air_jumps = MAX_AIR_JUMPS
		velocity.y = jump_velocity
		return 1
	if _air_jumps > 0:
		_air_jumps -= 1
		velocity.y = jump_velocity * AIR_JUMP_MULT
		_jump_ring()
		return 2
	return 0


func _jump_ring() -> void:
	## 二段跳：脚下一圈淡白光环迅速散开（克制版反馈，不做粒子）
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	SLAM_FX.spawn_ring(scene, global_position + Vector3(0.0, 0.08, 0.0), 1.5, Color(1, 1, 1), 0.42)


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
