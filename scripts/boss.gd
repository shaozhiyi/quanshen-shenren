extends Node3D
## 野生狗奶等 BOSS 的通用实体：外观可以是「六面贴图盒」，也可以是名册 model 字段指向的
## 外部 3D 模型（.glb/.gltf/.tscn，Hyper3D 出的车即走这条路），模型文件缺失时用
## scripts/boss_model.gd 的程序化低模顶上，数值/外观全部来自 scripts/boss_roster.gd。
## 名册 skills=false 的 BOSS 是"载具档"：不飞天不砸地不射星点，只缓慢驶近 + 贴身尾气掉血，
## 外加一招「锁定冲撞」（原地冻结锁位 → 沿撞击路径铺红色预警带 → 直线猛冲，全程不转向）。
## 大地图无敌；按 E 进入 BOSS 空间后可战。有技能的空内循环：
## 待机 → 前摇（配乐乐句A + 星点渐多环绕蓄力）→ 攻击（20 米飞天 + 日月交替两轮 + 玩家掉血
##      + 逐颗射出星点，单发命中 5 血）
##      → 空中追踪 2 秒（跟着玩家位置走）→ 锁定红圈 1 秒 → 砸落（圈内 -20 + 地裂）
##      → 落地后随机游走，进入下一轮。
## 时间轴按公开歌词时间戳标定；配乐路径由名册 song 字段给出（缺失/为空则静默同轴）。
##      载具档（skills=false）没有乐句时间轴：它的 song 是进战从头循环播放的背景乐。
## 可重复挑战：死亡沉地 3 秒后自动离开空间即复活回原位，每次开战都从满血开始（撤退同样重置）。
## 难度：三档（普通/困难/噩梦），血量·光环伤害·掉落收益逐级递增；首次仅普通，击败一次后按 R 调节。
##      名册给了 hp_by_diff 的 BOSS 直接用三档定值（如大运 2000/2500/3000），不吃倍率。

const ROSTER := preload("res://scripts/boss_roster.gd")
const BOSS_MODEL := preload("res://scripts/boss_model.gd")

@export var def_id := "dogmilk"      # 名册 id：决定外观与数值
@export var world_x := 18.0
@export var world_z := 18.0
@export var max_hp := 1000.0         # 普通档基准血量（由名册覆盖）
@export var scale_factor := 24.0     # 0.25m 盒 → 巨物的放大倍数（由名册覆盖）
@export var random_spawn := true      # 每局按地形随机挑一处落脚点
@export var spawn_min_dist := 35.0    # 距玩家出生点的距离带下界（由名册覆盖）
@export var spawn_max_dist := 65.0    # 距离带上界：保证"不会生成太远"
@export var spawn_max_slope := 0.93   # 地面法线 y 分量下限：坡太陡奶盒站不稳

var boss_name := "野生狗奶"           # 显示名（头顶标签 + HUD）
var reward_item := "dogmilk"          # 掉落物品 id
var _def: Dictionary = {}
var _face_dir := "res://assets/props/dogmilk/"
var _tint := Color(1, 1, 1)
var _aura_base := 0.3                 # 普通档光环每 0.1 秒伤害
var _reward_counts: Array = [2, 3, 4]
var _song_path := "res://assets/audio/song.mp3"
# ---- 外观来源（名册可选字段，缺省即老的贴图盒 BOSS）----
var _model_path := ""                 # 外部 3D 模型（.glb/.gltf/.tscn）
var _placeholder := ""                # 模型缺失时的程序化占位外观（"truck"）
var _model_scale := 1.0
var _model_y := 0.0                   # 模型资产自身的上下偏移（对齐"原点落地"用）
var _model_rot_y := 0.0               # 模型朝向修正（度）：外部资产可能车头朝 ±X/±Z
var _model_node: Node3D               # 实际挂上去的外观（模型或占位低模）
var _visual_source := "box"           # 实际生效的外观来源：model / placeholder / box
var _visual_y := 0.12                 # 整个外观离地高度（贴图盒原本浮 0.12）
var _box_size := Vector3.ZERO         # 碰撞盒；零向量 = 按 scale_factor 推导
# ---- 战斗风格（名册可选字段）----
var _hp_by_diff: Array = []           # 三档定值血量（非空则忽略 DIFF_HP_MULT）
const ARENA_FALLBACK_CENTER := Vector3(0.0, 100.0, 0.0)
var _arena_name := "white"            # 进战时切到哪套空间（"white"/"highway"）
var _has_skills := true               # false = 载具档，只驶近 + 尾气 + 锁定冲撞
var _chase_speed := 0.0               # 载具档的驶近速度（米/秒）
# ---- 「锁定冲撞」（大运）：锁位冻结 charge_lock 秒 → 沿锁定方向直线猛冲 ----
var _charge_lock := 0.0               # 0 = 没这招；>0 = 锁定（预警）时长
var _charge_units := 8.0              # 撞击行程 = 玩家冲刺距离 × 这个数
var _charge_mult := 3.0               # 撞击速度 = 玩家奔跑速度 × 这个数
var _charge_gap := 2.5                # 一次冲完后的冷却
var _charge_dmg := 60.0               # 撞上的伤害（一次冲撞只结算一次，仍吃减伤/无敌）
var _charge_t := 0.0                  # >0：正在原地锁定（倒计时）
var _charge_run := false              # true：正在冲
var _charge_left := 0.0               # 本轮还剩多少米没冲完
var _charge_cd := 0.0                 # >0：刚冲完，暂时不再起手
var _charge_hit := false              # 本轮已经撞上过，不重复掉血
var _charge_speed := 0.0              # 本轮实际冲撞速度（起手时按玩家奔跑速度算）
var _charge_dir := Vector3(0.0, 0.0, 1.0)   # 锁定瞬间钉死的撞击方向（XZ 单位向量）
var _aim_locked := false              # 锁定/冲撞期间车头不再转向
var _faces_player := true             # false = 载具档：车头只对着行驶方向
var _heading := 0.0                   # 载具档的车头朝向（弧度 yaw，+Z 为零）
var _bob_amp := 0.1                   # 待机上下浮动幅度
const TURN_RATE := 2.6                # 载具档未锁定时的转向速度（弧度/秒的近似系数）
# ---- 撞击路径预警带（红色条带，替代原来的圆形光环）----
var _lane: MeshInstance3D             # 挂在 BOSS 的父节点上：车冲出去它留在原地
var _lane_mat: StandardMaterial3D
var _lane_len := 0.0
var _lane_t := 0.0

# ---- 难度档位：每升一档血量与伤害增加，收益（狗奶掉落）同步增加 ----
const DIFF_NAMES := ["普通", "困难", "噩梦"]
const DIFF_HP_MULT := [1.0, 1.6, 2.4]        # 相对普通档基准血量的倍率
const DIFF_AURA_MULT := [1.0, 1.5, 2.0]      # 光环伤害倍率
const RESET_HP_ON_LEAVE := true              # 撤退也重置满血（false=保留已打掉的血量）

var hp := max_hp
var difficulty := 0                 # 当前挑战难度（默认最低档）
var _beats := 0                     # 已被击败次数：≥1 后开放难度调节
var _base_max_hp := 1000.0          # 普通基准血量（名册值）
var _aura_dmg := 0.3                # 当前难度的光环单跳伤害
var _dead := false
var _t := 0.0
var _visual: Node3D
var _hp_label: Label3D
var _label: Label3D
var _base_y := 0.0
var _arena_mode := false          # 只有进入 BOSS 空间才可被攻击
var _home_pos := Vector3.ZERO     # 大地图原位（进出空间时恢复）

# ---- 音乐同步战斗循环（时间轴取自公开歌词元数据，音频由玩家自备） ----
const MUSIC_AT := 0.0           # 音频直接从副歌"忘你不舍"起头，故起点=0
const WINDUP_TIME := 11.10      # 前摇时长：曲内"忘你不舍 寻你不休"唱完（下句入点）即升空
const ATTACK_TIME := 14.18      # 攻击时长：四个乐句
const DAY_NIGHT_CYCLES := 2.0   # 攻击窗口内日月交替几轮（1→2 = 快一倍，时长不变）
const CHARGE_GAP := 8.0         # 每轮释放完后待机（秒）
const MAX_STARS := 24           # 蓄满星点数
const FLY_HEIGHT := 20.25       # 飞天高度（13.5 × 1.5）
const WANDER_SPEED := 45.0      # 释放完后随机移动速度（单位/秒）
# ---- 砸落：技能放完不立刻落地，先在空中追人，再锁位砸下 ----
const TRACK_TIME := 2.0         # 空中停留并追踪玩家当前位置的时长
const TRACK_LERP := 1.6         # 追踪跟随强度：留点滞后，玩家持续跑动才甩得开
const MARK_TIME := 1.0          # 追踪位置固定后，红圈预警时长
const SLAM_DROP_TIME := 0.45    # 从空中砸向红圈的时长（越落越快）
const SLAM_DAMAGE := 20.0       # 砸中玩家扣血（仍会被防具减伤）
const SLAM_RADIUS := 6.0        # 红圈半径＝命中判定半径
const STAR_FLIGHT := 0.9        # 单颗星点的提前发射量（保证最后一颗在交替结束时刚好射出）
const STAR_SPEED := 42.0        # 星点初速（米/秒）
const STAR_MAX_FLY := 8.0       # 星点存在兜底上限：正常情况下飞到地板上才消失
const STAR_DAMAGE := 5.0        # 黄色星点命中伤害（基准；仍吃防具减伤/无敌免疫）
const STAR_RED_BONUS := 5.0     # 红色星点比基准再多这么多（=10）
const SLAM_FX := preload("res://scripts/slam_fx.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
## 玩家一次冲刺能位移多远（米）= 18 × 0.2 = 3.6。名册 charge_units 按它的倍数算撞击行程。
const DASH_DIST := float(PLAYER_SCRIPT.DASH_SPEED) * float(PLAYER_SCRIPT.DASH_DURATION)
var _phase := 0                 # 0待机 1前摇 2攻击(飞天) 4空中追踪 5红圈预警 6砸落
var _phase_t := 0.0
var _stars_fired := 0           # 本轮攻击已射出的星点数
var _slam_target := Vector3.ZERO    # 锁定的砸落点（XZ 有效）
var _slam_top := 0.0                # 起砸时的高度
var _slam_hit := false              # 上一次砸落是否命中（供测试/提示）
var _marker: MeshInstance3D         # 地面红圈
var _marker_mat: StandardMaterial3D
var _stars: Array[MeshInstance3D] = []
var _orbit := 0.0
var _music: AudioStreamPlayer
var _has_music := false
var _dmg_t := 0.0
var _arena_base_y := 0.0
var _music_tail := 0.0          # 攻击结束后歌曲再多播的剩余秒数
var _wander_target := Vector3.ZERO
var _wandering := false

signal died(target: Node)   # 多只 BOSS 同场，带上是谁死的


func set_arena_mode(b: bool) -> void:
	_arena_mode = b
	_phase = 0
	_phase_t = 0.0
	_dmg_t = 0.0
	_music_tail = 0.0
	_wandering = false
	_slam_hit = false
	_slam_target = Vector3.ZERO
	_show_marker(false)
	_hide_stars()
	_reset_charge()        # 载具档：半截冲撞/预警带不能留到下一次开战
	if _music != null and _music.playing:
		_music.stop()
	if b:
		_arena_base_y = position.y
		apply_difficulty()   # 每次开战都是一场完整的挑战
		if _has_music and not _has_skills:
			_music.play(0.0)   # 载具档：进战场就开唱（循环），撤退/击杀走上面的 stop 收尾
	else:
		if _dead:
			respawn()        # 击杀后离开空间 → 原地复活，可再次挑战
		elif RESET_HP_ON_LEAVE:
			hp = max_hp      # 中途撤退：BOSS 回满血，防止反复消耗打法
			_refresh_labels()
	var arena := arena_node()
	if arena != null:
		arena.set_day_night(0.0)


# ---- 难度：默认最低档，击败一次后由玩家按 R 调节 ----
func apply_difficulty() -> void:
	## 按当前难度重算血量与光环伤害（星点颜色是固定的红黄蓝绿规律，不随难度变）
	difficulty = clampi(difficulty, 0, DIFF_NAMES.size() - 1)
	if _hp_by_diff.size() == DIFF_NAMES.size():
		max_hp = float(_hp_by_diff[difficulty])       # 名册给了定值（大运 2000/2500/3000）
	else:
		max_hp = _base_max_hp * float(DIFF_HP_MULT[difficulty])
	hp = max_hp
	_aura_dmg = _aura_base * float(DIFF_AURA_MULT[difficulty])
	_refresh_labels()


func cycle_difficulty() -> int:
	## 切到下一档（循环）；未解锁或战斗中不允许，返回当前难度
	if not can_adjust_difficulty():
		return difficulty
	difficulty = (difficulty + 1) % DIFF_NAMES.size()
	apply_difficulty()
	return difficulty


func can_adjust_difficulty() -> bool:
	## 首次挑战固定普通档；击败过一次、且不在战斗中/未死亡时才能调节
	return _beats >= 1 and not _arena_mode and not _dead


func difficulty_name() -> String:
	return String(DIFF_NAMES[clampi(difficulty, 0, DIFF_NAMES.size() - 1)])


func reward_count() -> int:
	## 当前难度的掉落收益（数量由名册 reward_counts 给出）
	var i := clampi(difficulty, 0, _reward_counts.size() - 1)
	return int(_reward_counts[i])


func aura_damage() -> float:
	return _aura_dmg


func aura_base() -> float:
	return _aura_base


func get_reward_item() -> String:
	return reward_item


func times_beaten() -> int:
	return _beats


func respawn() -> void:
	## 沉地后复活：恢复外观高度、满血、待机相位并回到大地图原位
	_dead = false
	if _visual != null:
		_visual.position.y = _visual_y
		_visual.position.x = 0.0
	if _hp_label != null:
		_hp_label.visible = true
	_phase = 0
	_phase_t = 0.0
	_dmg_t = 0.0
	_music_tail = 0.0
	_wandering = false
	_slam_hit = false
	_show_marker(false)
	_hide_stars()
	_reset_charge()
	apply_difficulty()
	go_home()


func is_attacking() -> bool:
	## 2 飞天攻击 / 4 空中追踪 / 5 红圈预警 / 6 砸落 —— 整段空中阶段都算"正在出招"
	return _phase >= 2


func is_arena_mode() -> bool:
	return _arena_mode


# ---- 节点查找：BOSS 可能直接挂在 Main 下，也可能由 BossField 生成（层级多一层），
#      因此一律优先按分组查找，避免 "../Player" 这类相对路径在嵌套后取到 null ----
func _find(group: String, rel: String) -> Node:
	var n := get_tree().get_first_node_in_group(group)
	if n == null:
		n = get_node_or_null(rel)
	return n


func player_node() -> Node:
	return _find("player", "../Player")


func arena_name() -> String:
	## 这只 BOSS 的专属战场（玩家按 E 时据此挑空间节点）
	return _arena_name


func arena_node() -> Node:
	## 现在可能同时挂着好几套空间（纯白 / 国道），一律取"正激活"的那套；
	## 没有激活的再退回分组第一个（保持老代码行为）
	var first: Node = null
	for a in get_tree().get_nodes_in_group("arena"):
		if first == null:
			first = a
		if a.has_method("is_active") and bool(a.call("is_active")):
			return a
	return first if first != null else get_node_or_null("../Arena")


func ground_node() -> Node:
	return _find("ground", "../Ground")


func is_dead() -> bool:
	return _dead


func teleport_to(p: Vector3) -> void:
	position = p


func go_home() -> void:
	position = _home_pos


func place_near(spawn_point: Vector3, ground: Node, avoid: Array = []) -> bool:
	## 随机落点：只接受离玩家出生点 spawn_min~max_dist 米、坡度平缓、离边界有安全距离、
	## 且与其他 BOSS 至少相隔 30 米的位置；连续尝试失败则退回导出时的大地图坐标
	if ground == null or not ground.has_method("height_at"):
		return false
	var half := size_half(ground)
	for i in 160:
		var ang := randf() * TAU
		var dist := randf_range(spawn_min_dist, spawn_max_dist)
		var x := spawn_point.x + cos(ang) * dist
		var z := spawn_point.z + sin(ang) * dist
		if absf(x) > half or absf(z) > half:
			continue
		if ground.has_method("normal_at") and ground.call("normal_at", x, z).y < spawn_max_slope:
			continue
		var y: float = ground.call("height_at", x, z)
		if absf(y - spawn_point.y) > 26.0:
			continue   # 别把 BOSS 甩到深谷或绝壁顶上，玩家抬头找不到
		var clash := false
		for a in avoid:
			if Vector2(x, z).distance_to(Vector2(float(a.x), float(a.z))) < 30.0:
				clash = true
				break
		if clash:
			continue
		world_x = x
		world_z = z
		_base_y = y
		position = Vector3(x, y, z)
		_home_pos = position
		if _label != null:
			_label.position.y = box_height() + 1.2
		if _hp_label != null:
			_hp_label.position.y = box_height() + 0.6
		print("[boss] %s 落点 (%.1f, %.1f)，距出生点 %.1f 米" % [boss_name, x, z, Vector2(x - spawn_point.x, z - spawn_point.z).length()])
		return true
	print("[boss] %s 未找到合适落点，沿用默认坐标 (%.1f, %.1f)" % [boss_name, world_x, world_z])
	return false


func size_half(ground: Node) -> float:
	## 可用半径：地形半宽留 55 米边距，避免贴着边界墙/掉出地形外
	var s: float = float(ground.get("size")) if ground.get("size") != null else 500.0
	return maxf(s * 0.5 - 55.0, 80.0)


func box_height() -> float:
	## 碰撞盒高度（Label 挂在盒顶上方，落点变化时同步）
	return _box_size.y if _box_size.y > 0.0 else 0.25 * scale_factor


var _spawn_at := Vector3.INF    # 由 boss_field 预分配的落点（无则用 world_x/world_z）


func _load_def() -> void:
	## 从名册取本只 BOSS 的外观与数值；名册缺项时保留脚本默认值
	_def = ROSTER.def(def_id)
	if _def.is_empty():
		push_warning("boss: 名册里没有 %s，沿用脚本默认值" % def_id)
		return
	boss_name = String(_def.get("name", boss_name))
	_face_dir = String(_def.get("face_dir", _face_dir))
	_tint = _def.get("tint", _tint)
	scale_factor = float(_def.get("scale", scale_factor))
	max_hp = float(_def.get("base_hp", max_hp))
	_aura_base = float(_def.get("aura", _aura_base))
	reward_item = String(_def.get("reward", reward_item))
	_reward_counts = _def.get("reward_counts", _reward_counts)
	var band: Array = _def.get("band", [spawn_min_dist, spawn_max_dist])
	spawn_min_dist = float(band[0])
	spawn_max_dist = float(band[1])
	_song_path = String(_def.get("song", _song_path))
	# ---- 外观：外部模型 / 程序化占位 / 贴图盒 ----
	_model_path = String(_def.get("model", ""))
	_placeholder = String(_def.get("placeholder", ""))
	_model_scale = float(_def.get("model_scale", 1.0))
	_model_y = float(_def.get("model_y", 0.0))
	_model_rot_y = float(_def.get("model_rot_y", 0.0))
	_visual_y = float(_def.get("visual_y", 0.12))
	_bob_amp = float(_def.get("bob_amp", 0.1))
	var bx: Array = _def.get("box", [])
	if bx.size() == 3:
		_box_size = Vector3(float(bx[0]), float(bx[1]), float(bx[2]))
	else:
		_box_size = Vector3(0.09, 0.25, 0.06) * scale_factor
	# ---- 战斗风格 ----
	_hp_by_diff = _def.get("hp_by_diff", [])
	if _hp_by_diff.size() > 0:
		max_hp = float(_hp_by_diff[0])     # 基准血量取普通档定值，供 _base_max_hp 继承
	_has_skills = bool(_def.get("skills", true))
	_chase_speed = float(_def.get("chase", 0.0))
	_arena_name = String(_def.get("arena", "white"))
	# 冲撞技能（只给载具档的 BOSS 用）：配了 charge_lock 才算有这招
	_charge_lock = float(_def.get("charge_lock", 0.0))
	_charge_units = float(_def.get("charge_units", 4.0))
	_charge_mult = float(_def.get("charge_speed_mult", 1.5))
	_charge_gap = float(_def.get("charge_gap", 2.5))
	_charge_dmg = float(_def.get("charge_damage", 20.0))
	_faces_player = not bool(_def.get("no_turn", false))


func _ready() -> void:
	add_to_group("boss_unit")     # 实体：玩家/HUD 按这个组找"最近的那只 BOSS"
	_load_def()
	if _spawn_at != Vector3.INF:
		world_x = _spawn_at.x
		world_z = _spawn_at.z
	_base_max_hp = max_hp            # 名册的普通档基准，难度倍率在此基础上放大
	apply_difficulty()               # 先按名册把血量/光环伤害/星点色算好，避免未开战时读到默认 0.3
	var ground := ground_node()
	if ground != null and ground.has_method("height_at"):
		_base_y = ground.height_at(world_x, world_z)
	position = Vector3(world_x, _base_y, world_z)
	_home_pos = position

	_visual = Node3D.new()
	add_child(_visual)
	_build_visual()

	# 实体碰撞（剑射线与玩家阻挡）
	var body := StaticBody3D.new()
	body.add_to_group("boss")
	var csc := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _box_size
	csc.shape = box
	csc.position = Vector3(0, box.size.y * 0.5, 0)
	body.add_child(csc)
	add_child(body)

	_label = Label3D.new()
	_label.text = "%s · BOSS" % boss_name
	_label.position = Vector3(0, box.size.y + 1.2, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 72
	_label.modulate = Color(1, 0.95, 0.7)
	_label.outline_size = 24
	add_child(_label)

	_hp_label = Label3D.new()
	_hp_label.position = Vector3(0, box.size.y + 0.6, 0)
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.font_size = 56
	_hp_label.modulate = Color(0.4, 1.0, 0.45)
	_hp_label.outline_size = 18
	add_child(_hp_label)
	if _has_skills:
		_build_stars()
		_build_marker()
	elif _charge_lock > 0.0:
		_build_lane()          # 载具档的撞击路径预警带（红色条带，不是光环）
	_refresh_labels()
	# 可选战斗配乐：由名册 song 字段指定（为空或文件缺失则静默走同一时间轴）
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_has_music = _song_path != "" and ResourceLoader.exists(_song_path)
	if _has_music:
		_music.stream = load(_song_path)
		if not _has_skills and _music.stream is AudioStreamMP3:
			# 载具档没有"前摇/攻击"的乐句时间轴，这首歌就是整场战斗的背景乐 → 循环放，
			# 免得厚血仗打到一半没音乐（狗奶那档仍只走一遍副歌，靠 _music_tail 收尾）
			# 注意 AudioStreamMP3 只有 bool loop + loop_offset（秒），loop_mode 那套枚举是 WAV 的
			var mp3 := _music.stream as AudioStreamMP3
			mp3.loop = true
			mp3.loop_offset = 0.0


func _build_visual() -> void:
	## 外观优先级：名册 model（外部 3D 模型）> placeholder（程序化低模）> 六面贴图盒
	if _model_path != "" and ResourceLoader.exists(_model_path):
		var res: Resource = load(_model_path)
		if res is PackedScene:
			var node := (res as PackedScene).instantiate()
			if node is Node3D:
				node.scale = Vector3.ONE * _model_scale
				node.position = Vector3(0.0, _model_y, 0.0)
				node.rotation_degrees.y = _model_rot_y
				_visual.add_child(node)
				_model_node = node as Node3D
				_visual_source = "model"
				print("[boss] %s 采用模型 %s" % [boss_name, _model_path])
				return
			node.free()
		push_warning("boss: %s 存在但不是可用的 PackedScene，改用占位外观" % _model_path)
	if _placeholder == "truck":
		var t: Node3D = BOSS_MODEL.build_truck(_tint)
		t.scale = Vector3.ONE * _model_scale
		t.position = Vector3(0.0, _model_y, 0.0)
		t.rotation_degrees.y = _model_rot_y
		_visual.add_child(t)
		_model_node = t
		_visual_source = "placeholder"
		print("[boss] %s 采用占位低模（把 truck.glb 放进 assets/models/ 即自动换成真模型）" % boss_name)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _build_box_mesh()
	mi.scale = Vector3.ONE * scale_factor
	_visual.add_child(mi)
	_visual_source = "box"


func visual_source() -> String:
	return _visual_source


func has_skills() -> bool:
	return _has_skills


func aura_radius() -> float:
	## 无技能档的贴身伤害半径：以车身最长边的一半再留 2 米
	return maxf(_box_size.x, _box_size.z) * 0.5 + 2.0


func _build_marker() -> void:
	## 砸落预警红圈：本体子节点，贴地水平面片（直径=判定直径），默认隐藏
	_marker = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SLAM_RADIUS * 2.0, SLAM_RADIUS * 2.0)
	_marker.mesh = pm
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 贴地透明面片，投影会糊成一方块
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = SLAM_FX.ring_texture()
	mat.albedo_color = Color(1.0, 0.10, 0.08, 0.62)
	_marker.material_override = mat
	_marker_mat = mat
	_marker.visible = false
	add_child(_marker)


func _build_lane() -> void:
	## 撞击路径预警带：贴地的长条面片，宽 = 车宽留点边、长 = 撞击行程，
	## 从车头一直铺到撞击终点——玩家只要走出这条带子就不会被撞。
	## 刻意挂在 BOSS 的父节点上（不是子节点）：车冲出去之后带子留在原地，
	## 不会跟着车一起往前滑。纯特效，投影关掉免得在路面上糊出一块方影。
	_lane = MeshInstance3D.new()
	_lane_len = charge_dist()
	var pm := PlaneMesh.new()
	pm.size = Vector2(_box_size.x + 0.6, _lane_len)
	_lane.mesh = pm
	_lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD   # 沥青上是发光红带，不是灰雾
	mat.albedo_texture = SLAM_FX.lane_texture()
	mat.albedo_color = Color(1.0, 0.20, 0.14, 0.0)
	mat.uv1_scale = Vector3(1.0, _lane_len / 3.0, 1.0)   # 每 3 米一组朝前的箭头
	_lane.material_override = mat
	_lane_mat = mat
	_lane.visible = false
	var holder := get_parent()
	if holder != null:
		holder.add_child(_lane)


func _layout_lane() -> void:
	## 按锁定的车头朝向把带子摆到地面上（+Z = 车头方向，所以沿 fwd 推出中心点）
	if _lane == null:
		return
	var fwd := Vector3(sin(_heading), 0.0, cos(_heading))
	_lane.rotation.y = _heading
	_lane.global_position = global_position + fwd * (_box_size.z * 0.5 + _lane_len * 0.5) \
		+ Vector3(0.0, _arena_base_y + 0.07 - global_position.y, 0.0)


func _show_lane(b: bool) -> void:
	if _lane == null:
		return
	_lane.visible = b
	if b:
		_lane_t = 0.0
		if _lane_mat != null:
			_lane_mat.albedo_color = Color(1.0, 0.20, 0.14, 0.0)
		_layout_lane()


func _update_lane(delta: float) -> void:
	## 预警期：红带快速淡入、箭头朝撞击方向流动，临撞前 0.35 秒开始急促闪烁
	if _lane == null or not _lane.visible or _lane_mat == null:
		return
	_lane_t += delta
	var fade_in := clampf(_lane_t / 0.35, 0.0, 1.0)
	var panic := 1.0
	if _charge_lock > 0.0 and _charge_t < 0.35:
		panic = 0.55 + 0.45 * absf(sin(_lane_t * 26.0))
	_lane_mat.albedo_color = Color(1.0, 0.20, 0.14, 0.92 * fade_in * panic)
	_lane_mat.uv1_offset.y -= delta * 1.1      # 偏移递减 = 图案朝 +v（车头方向）流动


# ---- 蓄力星点：立体星点池（蓄力时逐个点亮，攻击期逐颗射出，与射出后的外观同一套网格）----
# 颜色规律固定为 红→黄→蓝→绿 循环：红=高伤(10)+快 1.5×，黄=常规(5)，蓝=5 伤 + 减速 5 秒 + 慢 0.7×，绿=无伤但回 5 血
func _build_stars() -> void:
	for i in MAX_STARS:
		var mi := MeshInstance3D.new()
		mi.mesh = SLAM_FX.star_mesh()       # 高 1 米，scale 即米数
		var kind := SLAM_FX.star_kind(i)
		var col: Color = SLAM_FX.star_color(kind)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = col
		mat.metallic = 0.2
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 2.4
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.set_meta("kind", kind)
		add_child(mi)
		_stars.append(mi)


func star_kind_of(i: int) -> String:
	## 第 i 颗蓄力星点的颜色种类（供测试/表现查询）
	if i < 0 or i >= _stars.size():
		return ""
	return String(_stars[i].get_meta("kind", SLAM_FX.star_kind(i)))


func star_damage_of(kind: String) -> float:
	## 该颜色种类的星点伤害：红色比基准多 STAR_RED_BONUS，绿色无伤害
	match kind:
		"red":
			return STAR_DAMAGE + STAR_RED_BONUS
		"green":
			return 0.0
		_:
			return STAR_DAMAGE


func _face_mat(tex_file: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(_face_dir + tex_file)
	m.albedo_color = _tint        # 名册着色：同一套贴图换色即可做出不同 BOSS
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_box_mesh() -> ArrayMesh:
	## 六面各一个 surface：顶点按"从外侧看逆时针"排列，法线显式朝外
	var W := 0.09
	var H := 0.25
	var D := 0.06
	var hx := W / 2.0
	var hz := D / 2.0
	# 面定义: [贴图, 法线, 4顶点(外视逆时针)]
	var defs: Array = [
		["front.png", Vector3(0, 0, 1), [Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, H, hz), Vector3(-hx, H, hz)]],
		["back.png", Vector3(0, 0, -1), [Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), Vector3(-hx, H, -hz), Vector3(hx, H, -hz)]],
		["side.png", Vector3(1, 0, 0), [Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(hx, H, -hz), Vector3(hx, H, hz)]],
		["side.png", Vector3(-1, 0, 0), [Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(-hx, H, hz), Vector3(-hx, H, -hz)]],
		["top.png", Vector3(0, 1, 0), [Vector3(-hx, H, hz), Vector3(hx, H, hz), Vector3(hx, H, -hz), Vector3(-hx, H, -hz)]],
		["bottom.png", Vector3(0, -1, 0), [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]],
	]
	var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var mesh := ArrayMesh.new()
	for def in defs:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var verts: Array = def[2]
		var n: Vector3 = def[1]
		st.set_material(_face_mat(def[0]))
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit().surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, _face_mat(def[0]))
	return mesh


func _refresh_labels() -> void:
	## 名称标签 = 难度，血条标签 = 当前血量/上限 + 该档掉落收益
	if _label != null and not _dead:
		_label.text = "%s · %s难度" % [boss_name, difficulty_name()]
	if _hp_label != null:
		_hp_label.text = "HP %d / %d ｜ 掉落 ×%d" % [int(hp), int(max_hp), reward_count()]


func take_damage(amount: int) -> void:
	if _dead or not _arena_mode:
		return   # 大地图上不可直接攻击，须按 E 进入 BOSS 空间
	hp = maxf(hp - amount, 0.0)
	_refresh_labels()
	if hp <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	_beats += 1          # 击败一次后开放难度调节
	_label.text = "%s 已被缴获" % boss_name
	_hp_label.visible = false
	_music_tail = 0.0
	_reset_charge()      # 死在半截冲撞里：立刻收掉预警带，也别再往前滑
	if _music != null and _music.playing:
		_music.stop()
	died.emit(self)          # 先记账再通知，玩家侧按 reward_count() 发奖


func _process(delta: float) -> void:
	_t += delta
	if _dead:
		# 沉地消失
		_visual.position.y = maxf(_visual.position.y - delta * 1.2, -box_height() * 0.9)
		return
	# 正面（+Z）转向：贴图盒 BOSS 是"梗脸永远对着你"，载具档按车头条线走
	var player := player_node()
	var spd := 0.0
	if player != null:
		var d: Vector3 = player.global_position - global_position
		if _faces_player:
			_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(d.x, d.z), minf(1.0, delta * 3.0))
		else:
			# 载具档：车头只对着行驶方向；一旦锁定冲撞就整段钉死，直到撞完才恢复转向
			if not _aim_locked:
				_heading = lerp_angle(_heading, atan2(d.x, d.z), minf(1.0, delta * TURN_RATE))
			_visual.rotation.y = _heading
	_visual.position.y = _visual_y + _bob_amp * sin(_t * 1.4)
	_visual.position.x = 0.0
	if _arena_mode:
		if _has_skills:
			_update_windup(delta)
		else:
			spd = _update_truck_ai(delta)     # 大运：缓慢驶近 + 「锁定冲撞」
	_animate_wheels(delta, spd)


func _animate_wheels(delta: float, speed: float) -> void:
	## 车轮滚动：外观里有名为 "Wheels" 的节点（占位低模自带，外部模型可选）就按速度转
	if speed <= 0.001 or _model_node == null:
		return
	var wheels := _model_node.find_child("Wheels", true, false)
	if wheels == null:
		return
	var r := maxf(float(wheels.get_meta("radius", 0.55)), 0.05)
	var ang := speed * delta / r
	for w in wheels.get_children():
		if w is Node3D:
			(w as Node3D).rotation.x += ang


# ---- 音乐同步战斗循环：待机 → 前摇(乐句A+星点渐多) → 攻击(飞天+日月交替+掉血) → 落地 ----
func _update_windup(delta: float) -> void:
	_phase_t += delta
	if _music_tail > 0.0:
		_music_tail -= delta
		if _music_tail <= 0.0 and _music != null and _music.playing:
			_music.stop()
	var arena := arena_node()
	var player := player_node()
	var prog := 0.0
	if _phase == 1:
		prog = clampf(_phase_t / WINDUP_TIME, 0.0, 1.0)
	elif _phase >= 2:
		prog = 1.0
	_orbit += delta * (2.2 + 4.0 * prog)
	match _phase:
		0:
			_hide_stars()
			_update_wander(delta)
			if _phase_t >= CHARGE_GAP:
				_phase = 1
				_phase_t = 0.0
				if _has_music and _music != null:
					_music.play(MUSIC_AT)   # 前摇乐句起点，后续相位靠连续播放保持同步
		1:
			# 蓄力进度越高，点亮的星点越多
			var lit := int(prog * float(MAX_STARS))
			for i in MAX_STARS:
				_stars[i].visible = i < lit
			_layout_stars(prog)
			# 蓄力震颤
			_visual.position.x = 0.06 * sin(_t * 34.0) * prog
			if _phase_t >= WINDUP_TIME:
				_phase = 2
				_phase_t = 0.0
				_dmg_t = 0.0
		2:
			# 攻击：飞天 + 日月交替 + 逐颗射出星点（命中各 5 血）+ 每 0.1 秒掉 1 血
			var at := clampf(_phase_t / ATTACK_TIME, 0.0, 1.0)
			position.y = _arena_base_y + FLY_HEIGHT * minf(1.0, _phase_t / 1.4) + 0.5 * sin(_t * 2.1)
			_visual.position.x = 0.12 * sin(_t * 50.0)
			# 发射窗口 = 交替时长 - 单颗飞行时间 → 交替结束正好射完最后一颗
			var want := int((_phase_t / maxf(ATTACK_TIME - STAR_FLIGHT, 0.001)) * float(MAX_STARS))
			while _stars_fired < clampi(want, 0, MAX_STARS):
				_fire_star(_stars_fired, player)
			_layout_stars(1.0)
			if arena != null:
				# 攻击窗口内跑 DAY_NIGHT_CYCLES 个整周期（=2 → 昼→夜→昼→夜→昼，交替快一倍）
				arena.set_day_night((1.0 - cos(TAU * at * DAY_NIGHT_CYCLES)) * 0.5)
			_dmg_t += delta
			while _dmg_t >= 0.1:
				_dmg_t -= 0.1
				if player != null and player.has_method("take_damage") and not _dead:
					player.take_damage(_aura_dmg)   # 普通 0.3/tick，随难度倍率提升
			if _phase_t >= ATTACK_TIME:
				_music_tail = 0.8   # 歌曲多播 0.8 秒后收尾
				if arena != null:
					arena.set_day_night(0.0)
				_set_phase(4)       # 技能放完不立刻落地：先在空中追人
		4:
			# 空中停留 2 秒：持续追踪玩家当前位置（有滞后，跑得快就追不上）
			position.y = _arena_base_y + FLY_HEIGHT + 0.35 * sin(_t * 2.4)
			_visual.position.x = 0.10 * sin(_t * 42.0)
			if player != null:
				var k := 1.0 - exp(-TRACK_LERP * delta)
				position.x = lerpf(position.x, player.global_position.x, k)
				position.z = lerpf(position.z, player.global_position.z, k)
				_clamp_arena()
			_layout_stars(1.0)
			if _phase_t >= TRACK_TIME:
				_slam_target = Vector3(position.x, _arena_base_y, position.z)   # 追踪位置就此固定
				_set_phase(5)
				_show_marker(true)
		5:
			# 红圈预警 1 秒：本体悬停在圈正上方，玩家有时间跑出圈外
			position.x = _slam_target.x
			position.z = _slam_target.z
			position.y = _arena_base_y + FLY_HEIGHT + 0.25 * sin(_t * 7.0)
			_visual.position.x = 0.16 * sin(_t * 60.0)
			_update_marker(clampf(_phase_t / MARK_TIME, 0.0, 1.0))
			_layout_stars(1.0)
			if _phase_t >= MARK_TIME:
				_slam_top = position.y
				_set_phase(6)
		6:
			# 砸落：越落越快，落地瞬间判定命中 + 地裂特效
			var p := clampf(_phase_t / SLAM_DROP_TIME, 0.0, 1.0)
			position.y = lerpf(_slam_top, _arena_base_y, p * p)
			_layout_stars(1.0)
			if _phase_t >= SLAM_DROP_TIME:
				position.y = _arena_base_y
				_do_slam_impact(player)
				_set_phase(0)
				_hide_stars()
				_pick_wander_target()   # 砸完开始正常移动


func _fire_star(i: int, player: Node) -> void:
	## 把第 i 颗环绕星点射出去：从它当前的环绕位置朝玩家当时所在方向飞出，池子里熄灭。
	## 颜色与效果按红黄蓝绿规律（见 slam_fx.star_kind）：红 10 伤、黄 5 伤、蓝 5 伤 + 减速、绿 0 伤 + 回血
	_stars_fired = i + 1        # 先计数，异常分支也不会让调用方的 while 卡死
	if i < 0 or i >= _stars.size():
		return
	var st := _stars[i]
	var from := st.global_position
	st.visible = false
	var kind := star_kind_of(i)
	# 红 1.5×、蓝 0.7×：颜色决定快慢，弹道补偿也得按各自速度算
	var spd := STAR_SPEED * SLAM_FX.star_speed_mult(kind)
	var to := from + Vector3(0.0, -8.0, 0.0)
	if player != null and is_instance_valid(player):
		to = player.global_position + Vector3(0.0, 0.6, 0.0)
		# 弹道补偿：星点带重力下坠，按飞行时间把瞄准点抬高，离得远也打得到你脚下
		var fly_t := from.distance_to(to) / spd
		to.y += 0.5 * SLAM_FX.STAR_GRAVITY * fly_t * fly_t
	var dir := to - from
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, -1.0, 0.0)
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	# 生命参数只作兜底上限：星点现在是碰到地板才消失，不再飞到一半自己没了
	# （速度传基准值即可：spawn_star 内部会按颜色种类再乘 1.5 / 0.7）
	SLAM_FX.spawn_star(scene, from, dir.normalized(), STAR_SPEED, STAR_MAX_FLY,
		st.scale.x, star_damage_of(kind), kind)


func _layout_stars(prog: float) -> void:
	## 星点绕身体螺旋环绕：半径随蓄力收缩、高度错开、尺寸微涨
	var n := MAX_STARS
	for i in n:
		var a := _orbit + TAU * float(i) / float(n)
		var radius := lerpf(4.0, 2.6, prog)
		var h := 0.7 + fmod(float(i) * 1.37, 5.8)
		var s: float = _stars[i].scale.x
		var target := lerpf(1.0, 1.7, prog) * (1.0 + 0.15 * sin(_t * 9.0 + float(i)))
		_stars[i].position = Vector3(cos(a) * radius, h, sin(a) * radius)
		_stars[i].scale = Vector3.ONE * lerpf(s, target, 0.2)
		# 立体星点：各自快转 + 少量翻滚，相位错开，蓄力期就看得出是"一圈星点"
		_stars[i].rotation = Vector3(_t * 1.1 + float(i), _t * 3.4 + float(i) * 0.7, 0.0)


func _hide_stars() -> void:
	## 收起全部星点并重置发射计数（下一轮前摇重新蓄满）
	_stars_fired = 0
	for st in _stars:
		st.visible = false


func _set_phase(p: int) -> void:
	## 统一换相位（顺带把计时清零，避免各处漏写 _phase_t = 0.0）
	_phase = p
	_phase_t = 0.0


func _clamp_arena() -> void:
	## 追踪时别把 BOSS 甩出场地（按当前空间自己的中心与半宽，留 40 米边距）
	var arena := arena_node()
	var c := ARENA_FALLBACK_CENTER
	var half := 400.0
	if arena != null:
		if arena.has_method("center"):
			c = arena.call("center")
		if arena.has_method("bounds_half"):
			half = float(arena.call("bounds_half"))
	var lim := maxf(half - 40.0, 20.0)
	position.x = clampf(position.x, c.x - lim, c.x + lim)
	position.z = clampf(position.z, c.z - lim, c.z + lim)


func _do_slam_impact(player: Node) -> void:
	## 砸地瞬间：地裂特效 + 圈内命中判定（命中扣 SLAM_DAMAGE，仍吃防具减伤/无敌）
	_show_marker(false)
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	SLAM_FX.spawn_slam(scene, Vector3(position.x, _arena_base_y + 0.02, position.z), SLAM_RADIUS)
	_slam_hit = false
	if player != null and is_instance_valid(player):
		var d := Vector2(player.global_position.x - position.x, player.global_position.z - position.z).length()
		if d <= SLAM_RADIUS:
			_slam_hit = true
			if player.has_method("take_damage"):
				player.take_damage(SLAM_DAMAGE)


func slam_hit() -> bool:
	return _slam_hit


func _show_marker(b: bool) -> void:
	if _marker != null:
		_marker.visible = b


func _update_marker(prog: float) -> void:
	## 红圈：贴在锁定点的地面上，随预警进度由淡转浓、轻微脉动
	if _marker == null:
		return
	_marker.visible = true
	# 本体在 FLY_HEIGHT 上，标记是它的子节点 → 反向偏移才能贴住地面
	_marker.position = Vector3(0.0, (_arena_base_y + 0.06) - position.y, 0.0)
	var pulse := 1.0 + 0.06 * sin(_t * 12.0)
	var s := lerpf(0.72, 1.0, clampf(prog * 1.6, 0.0, 1.0)) * pulse
	_marker.scale = Vector3(s, 1.0, s)
	if _marker_mat != null:
		_marker_mat.albedo_color = Color(1.0, 0.10, 0.08, lerpf(0.62, 1.0, prog))


func _pick_wander_target() -> void:
	## 释放完技能后：在当前位置随机选一个最多 100 单位的新落点，夹在场地内
	var ang := randf() * TAU
	var dist := randf() * 100.0
	var t := position + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
	var lim := 360.0                 # 场地半宽 400，留 40 边距
	t.x = clampf(t.x, -lim, lim)
	t.z = clampf(t.z, -lim, lim)
	t.y = _arena_base_y
	_wander_target = t
	_wandering = true


func _update_wander(delta: float) -> void:
	if not _wandering:
		return
	var to := _wander_target - position
	to.y = 0.0
	var d := to.length()
	if d <= 0.5:
		position.x = _wander_target.x
		position.z = _wander_target.z
		position.y = _arena_base_y
		_wandering = false
		return
	var step := minf(WANDER_SPEED * delta, d)
	position += to.normalized() * step
	position.y = _arena_base_y


func _update_chase(delta: float) -> float:
	## 载具档（大运）的驶近：只缓慢朝玩家开过去。不飞天、不蓄力、不砸地、不射星点，
	## 也不改动日月。掉血在 _tick_aura() 里单独结算。返回本帧速度（米/秒）。
	var player := player_node()
	if player == null or _dead:
		return 0.0
	var to: Vector3 = player.global_position - position
	to.y = 0.0
	var d := to.length()
	# 停车距离按车身半长算：长车头只留 2 米会直接插进玩家模型里
	var stop := maxf(2.0, _box_size.z * 0.5 + 1.0)
	var step := 0.0
	if d > stop and _chase_speed > 0.0:
		step = minf(_chase_speed * delta, d - stop)     # 留出停车距离，不会顶进玩家模型
		_move_truck(to.normalized() * step)
	_clamp_arena()
	return step / maxf(delta, 0.0001)


func _move_truck(step: Vector3) -> void:
	## 大运的位移一律过一遍战场的 confine()：它是"焊死在国道上"的车，不会斜着压进
	## 中央隔离带、也不会冲出右侧路肩（纯白空间没有这个方法 = 不限制）。
	position += step
	var arena := arena_node()
	if arena != null and arena.has_method("confine"):
		position = arena.call("confine", position)
	position.y = _arena_base_y


func _tick_aura(delta: float) -> void:
	## 贴身尾气：玩家进了 aura_radius 就持续掉血。刻意与"车动不动"解耦——
	## 锁定预警期间车是停着的，但黑烟照样熏人（否则玩家站着等它撞反而最安全）。
	var player := player_node()
	if player == null or _dead:
		return
	if global_position.distance_to(player.global_position) > aura_radius():
		return
	_dmg_t += delta
	while _dmg_t >= 0.1:
		_dmg_t -= 0.1
		if player.has_method("take_damage"):
			player.take_damage(_aura_dmg)


# ---- 「锁定冲撞」：锁位冻结 → 沿撞击路径铺红色预警带 → 直线猛冲（全程不转向）----
func charge_dist() -> float:
	## 撞击行程 = 玩家一次冲刺的位移 × charge_units（默认 3.6 × 8 ≈ 28.8 米）
	return _charge_units * DASH_DIST


func charge_reach() -> float:
	## 这一撞最远能碰到你多远：车头再往前冲完整段行程，加上车头本身离车身中心半个车长
	return charge_dist() + _box_size.z * 0.5


func charge_speed_ref() -> float:
	## 冲撞速度 = 玩家奔跑速度（步行速度 × 2）× charge_speed_mult，默认 10 × 3 = 30 米/秒
	var p := player_node()
	var walk := 5.0
	if p != null and p.get("move_speed") != null:
		walk = float(p.get("move_speed"))
	return walk * float(PLAYER_SCRIPT.RUN_MULT) * _charge_mult


func _reset_charge() -> void:
	## 进/出空间、死亡、复活时把冲撞状态清干净（预警带也一并收掉）
	_charge_t = 0.0
	_charge_run = false
	_charge_left = 0.0
	_charge_cd = 0.0
	_charge_hit = false
	_charge_speed = 0.0
	_aim_locked = false
	_charge_dir = Vector3(sin(_heading), 0.0, cos(_heading))
	_show_lane(false)


func charging() -> bool:
	return _charge_run


func locked() -> bool:
	return _charge_t > 0.0


func _begin_lock(player: Node) -> void:
	## 锁位：车头对准玩家此刻的位置，方向就此钉死（之后不会再转向），
	## 同时沿撞击路径在地面铺一条红色预警带 —— 玩家有 charge_lock 秒走出这条带子
	var dir: Vector3 = player.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3(sin(_heading), 0.0, cos(_heading))
	_charge_dir = dir.normalized()
	_heading = atan2(_charge_dir.x, _charge_dir.z)
	_aim_locked = true
	_charge_hit = false
	_charge_speed = charge_speed_ref()
	_charge_t = _charge_lock
	_show_lane(true)


func _fire_charge() -> void:
	## 预警结束，真的开撞。红带留在原地淡出（车正好从它上面压过去）
	_charge_t = 0.0
	_charge_run = true
	_charge_left = charge_dist()


func _tick_charge(delta: float) -> float:
	## 冲撞中：只沿锁定那一刻的方向直线推进，全程不踩方向盘；撞上一次算一次伤害
	var step := minf(_charge_speed * delta, maxf(_charge_left, 0.0))
	var from := global_position
	_move_truck(_charge_dir * step)
	_charge_left -= step
	_fade_lane(delta)
	if not _charge_hit and _touch_player(from, global_position):
		_charge_hit = true
	if _charge_left <= 0.001:
		_end_charge()
	return _charge_speed


func _end_charge() -> void:
	_charge_run = false
	_charge_left = 0.0
	_charge_cd = _charge_gap
	_aim_locked = false
	_show_lane(false)
	# 撞到底的动静：地裂 + 一蓬尘（伤害是在冲撞过程中判的，这里纯特效）
	var at := Vector3(global_position.x, _arena_base_y + 0.05, global_position.z)
	SLAM_FX.spawn_slam(get_parent(), at, maxf(charge_dist() * 0.35, 4.0), Color(1.0, 0.60, 0.25))


func _touch_player(from: Vector3, to: Vector3) -> bool:
	## 命中判定用"本帧起点→终点"这段车辙 + 半车宽：30 米/秒时一帧就跨半米，
	## 贴着车侧的人不会漏判，帧率低也不会直接穿过去。伤害仍吃防具减伤与无敌免疫。
	var player := player_node()
	if player == null or _dead:
		return false
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var p := Vector2(player.global_position.x, player.global_position.z)
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 0.000001 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	if (a + ab * t).distance_to(p) > _box_size.x * 0.5 + 0.7:
		return false
	if player.has_method("take_damage"):
		player.take_damage(_charge_dmg)
	return true


func _fade_lane(delta: float) -> void:
	if _lane == null or not _lane.visible or _lane_mat == null:
		return
	var col: Color = _lane_mat.albedo_color
	col.a = maxf(col.a - delta * 1.6, 0.0)
	_lane_mat.albedo_color = col


func _update_truck_ai(delta: float) -> float:
	## 大运的一帧决策：尾气照算 → 正在冲撞就直线推进 → 正在锁定就整帧冻住（连驶近也不走，
	## 否则会出现轮子停着、车身还在往前滑的怪相）→ 都不在就缓慢驶近并判断要不要锁位。
	## 返回本帧用于车轮滚动的速度（米/秒）。
	_tick_aura(delta)          # 掉血与"动不动"无关，放在最前面，冻结/冲撞分支也照算
	if _charge_run:
		return _tick_charge(delta)
	if _charge_t > 0.0:
		_charge_t -= delta
		_update_lane(delta)
		if _charge_t <= 0.0:
			_fire_charge()
		return 0.0
	var spd := _update_chase(delta)
	if _charge_cd > 0.0:
		_charge_cd -= delta
	elif _charge_lock > 0.0:
		var player := player_node()
		# 出手条件：玩家站进了"车头再往前冲一段"能够到的那条带子里
		if player != null and _dist_xz(global_position, player.global_position) <= charge_reach():
			_begin_lock(player)
			return 0.0
	return spd


func _dist_xz(a: Vector3, b: Vector3) -> float:
	## 水平距离（不算高差）：玩家站在地板上会比车身原点高 1 米多，按 3D 距离判会偏
	return Vector2(a.x - b.x, a.z - b.z).length()
