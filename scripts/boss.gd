extends Node3D
## 野生狗奶 BOSS：巨型梗奶盒（Godot 内 SurfaceTool 程序化六面贴图盒，不依赖外部 glb）。
## 大地图无敌；按 E 进入 BOSS 空间后可战。空间内循环：
## 待机 → 前摇（配乐乐句A + 星点渐多环绕蓄力）→ 攻击（飞天 + 场景日月交替 + 玩家掉血）→ 落地。
## 时间轴按公开歌词时间戳标定；完整歌曲置于 assets/audio/song.mp3 即自动配音（缺失则静默同轴）。
## 可重复挑战：死亡沉地 3 秒后自动离开空间即复活回原位，每次开战都从满血开始（撤退同样重置）。
## 难度：三档（普通/困难/噩梦），血量·光环伤害·掉落收益逐级递增；首次仅普通，击败一次后按 R 调节。

@export var world_x := 18.0
@export var world_z := 18.0
@export var max_hp := 1000.0
@export var scale_factor := 24.0  # 0.25m 盒 → 6m 巨物

const FACE_DIR := "res://assets/props/dogmilk/"

# ---- 难度档位：每升一档血量与伤害增加，收益（狗奶掉落）同步增加 ----
const DIFF_NAMES := ["普通", "困难", "噩梦"]
const DIFF_HP_MULT := [1.0, 1.6, 2.4]        # 相对 max_hp（普通基准）的血量倍率
const DIFF_AURA_MULT := [1.0, 1.5, 2.0]      # 光环伤害倍率
const DIFF_REWARD := [2, 3, 4]               # 击败掉落的野生狗奶数量
const DIFF_STAR_COLOR := [Color(1, 0.92, 0.55), Color(1, 0.55, 0.25), Color(0.78, 0.45, 1.0)]
const RESET_HP_ON_LEAVE := true              # 撤退也重置满血（false=保留已打掉的血量）

var hp := max_hp
var difficulty := 0                 # 当前挑战难度（默认最低档）
var _beats := 0                     # 已被击败次数：≥1 后开放难度调节
var _base_max_hp := 1000.0          # 普通基准血量（@export 值）
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
const SONG_PATH := "res://assets/audio/song.mp3"   # 完整歌曲放这里即自动启用
const MUSIC_AT := 0.0           # 音频直接从副歌"忘你不舍"起头，故起点=0
const WINDUP_TIME := 11.10      # 前摇时长：曲内"忘你不舍 寻你不休"唱完（下句入点）即升空
const ATTACK_TIME := 14.18      # 攻击时长：四个乐句
const LAND_TIME := 1.2          # 落地缓降
const CHARGE_GAP := 8.0         # 每轮释放完后待机（秒）
const MAX_STARS := 24           # 蓄满星点数
const FLY_HEIGHT := 13.5        # 飞天高度（原 9.0 × 1.5）
const WANDER_SPEED := 45.0      # 释放完后随机移动速度（单位/秒）
const AURA_DMG := 0.3           # 普通档：攻击期每 0.1 秒对玩家造成的伤害（难度再乘倍率）
var _phase := 0                 # 0待机 1前摇 2攻击(飞天) 3落地
var _phase_t := 0.0
var _stars: Array[MeshInstance3D] = []
var _star_tex: ImageTexture
var _orbit := 0.0
var _music: AudioStreamPlayer
var _has_music := false
var _dmg_t := 0.0
var _arena_base_y := 0.0
var _music_tail := 0.0          # 攻击结束后歌曲再多播的剩余秒数
var _wander_target := Vector3.ZERO
var _wandering := false

signal died


func set_arena_mode(b: bool) -> void:
	_arena_mode = b
	_phase = 0
	_phase_t = 0.0
	_dmg_t = 0.0
	_music_tail = 0.0
	_wandering = false
	_hide_stars()
	if _music != null and _music.playing:
		_music.stop()
	if b:
		_arena_base_y = position.y
		apply_difficulty()   # 每次开战都是一场完整的挑战
	else:
		if _dead:
			respawn()        # 击杀后离开空间 → 原地复活，可再次挑战
		elif RESET_HP_ON_LEAVE:
			hp = max_hp      # 中途撤退：BOSS 回满血，防止反复消耗打法
			_refresh_labels()
	var arena := get_node_or_null("../Arena")
	if arena != null:
		arena.set_day_night(0.0)


# ---- 难度：默认最低档，击败一次后由玩家按 R 调节 ----
func apply_difficulty() -> void:
	## 按当前难度重算血量与光环伤害，并给蓄力星点上色（越难越凶）
	difficulty = clampi(difficulty, 0, DIFF_NAMES.size() - 1)
	max_hp = _base_max_hp * float(DIFF_HP_MULT[difficulty])
	hp = max_hp
	_aura_dmg = AURA_DMG * float(DIFF_AURA_MULT[difficulty])
	var col: Color = DIFF_STAR_COLOR[difficulty]
	for st in _stars:
		var mat := st.material_override as StandardMaterial3D
		if mat != null:
			mat.emission = col
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
	## 当前难度的掉落收益（狗奶数量）
	return int(DIFF_REWARD[clampi(difficulty, 0, DIFF_REWARD.size() - 1)])


func aura_damage() -> float:
	return _aura_dmg


func times_beaten() -> int:
	return _beats


func respawn() -> void:
	## 沉地后复活：恢复外观高度、满血、待机相位并回到大地图原位
	_dead = false
	if _visual != null:
		_visual.position.y = 0.12
		_visual.position.x = 0.0
	if _hp_label != null:
		_hp_label.visible = true
	_phase = 0
	_phase_t = 0.0
	_dmg_t = 0.0
	_music_tail = 0.0
	_wandering = false
	_hide_stars()
	apply_difficulty()
	go_home()


func is_attacking() -> bool:
	return _phase == 2


func is_arena_mode() -> bool:
	return _arena_mode


func is_dead() -> bool:
	return _dead


func teleport_to(p: Vector3) -> void:
	position = p


func go_home() -> void:
	position = _home_pos


func _ready() -> void:
	add_to_group("boss")
	_base_max_hp = max_hp            # @export 值即"普通"基准，难度倍率在此基础上放大
	var ground := get_node_or_null("../Ground")
	if ground != null and ground.has_method("height_at"):
		_base_y = ground.height_at(world_x, world_z)
	position = Vector3(world_x, _base_y, world_z)
	_home_pos = position

	_visual = Node3D.new()
	add_child(_visual)
	var mi := MeshInstance3D.new()
	mi.mesh = _build_box_mesh()
	mi.scale = Vector3.ONE * scale_factor
	_visual.add_child(mi)

	# 实体碰撞（剑射线与玩家阻挡）
	var body := StaticBody3D.new()
	body.add_to_group("boss")
	var csc := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.09, 0.25, 0.06) * scale_factor
	csc.shape = box
	csc.position = Vector3(0, box.size.y * 0.5, 0)
	body.add_child(csc)
	add_child(body)

	_label = Label3D.new()
	_label.text = "野生狗奶 · BOSS"
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
	_build_stars()
	_refresh_labels()
	# 可选战斗配乐：玩家自备 assets/audio/song.mp3（存在即启用，缺失则静默走同一时间轴）
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_has_music = ResourceLoader.exists(SONG_PATH)
	if _has_music:
		_music.stream = load(SONG_PATH)


# ---- 蓄力星点：程序化四角星贴图 + 公告板小面片（池，蓄力时逐个点亮） ----
func _build_stars() -> void:
	_star_tex = _make_star_texture()
	for i in MAX_STARS:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		mi.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = _star_tex
		mat.emission_enabled = true
		mat.emission = Color(1, 0.92, 0.55)
		mat.emission_energy_multiplier = 3.6
		mi.material_override = mat
		mi.visible = false
		add_child(mi)
		_stars.append(mi)


func _make_star_texture() -> ImageTexture:
	## 32x32 四角星：十字星芒 + 亮芯，边缘渐隐
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := s * 0.5
	for y in s:
		for x in s:
			var dx := (x - c + 0.5) / c
			var dy := (y - c + 0.5) / c
			var v := 0.0
			if absf(dx * dy) < 0.05 and absf(dx) + absf(dy) < 1.0:
				v = 1.0 - (absf(dx) + absf(dy))
			var r := sqrt(dx * dx + dy * dy)
			if r < 0.34:
				v = maxf(v, 1.0 - r * 2.6)
			if v > 0.0:
				img.set_pixel(x, y, Color(1, 0.97, 0.78, clampf(v * 1.35, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _face_mat(tex_file: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(FACE_DIR + tex_file)
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
		_label.text = "野生狗奶 · %s难度" % difficulty_name()
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
	_label.text = "野生狗奶 已被缴获"
	_hp_label.visible = false
	_music_tail = 0.0
	if _music != null and _music.playing:
		_music.stop()
	died.emit()          # 先记账再通知，玩家侧按 reward_count() 发奖


func _process(delta: float) -> void:
	_t += delta
	if _dead:
		# 沉地消失
		_visual.position.y = maxf(_visual.position.y - delta * 1.2, -0.25 * 24.0 * 0.9)
		return
	# 正面（+Z）始终转向玩家：梗脸永远对着你
	var player := get_node_or_null("../Player")
	if player != null:
		var d: Vector3 = player.global_position - global_position
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(d.x, d.z), minf(1.0, delta * 3.0))
	_visual.position.y = 0.12 + 0.1 * sin(_t * 1.4)
	_visual.position.x = 0.0
	if _arena_mode:
		_update_windup(delta)


# ---- 音乐同步战斗循环：待机 → 前摇(乐句A+星点渐多) → 攻击(飞天+日月交替+掉血) → 落地 ----
func _update_windup(delta: float) -> void:
	_phase_t += delta
	if _music_tail > 0.0:
		_music_tail -= delta
		if _music_tail <= 0.0 and _music != null and _music.playing:
			_music.stop()
	var arena := get_node_or_null("../Arena")
	var player := get_node_or_null("../Player")
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
			# 攻击：飞天 + 日月交替 + 每 0.1 秒掉 1 血
			var at := clampf(_phase_t / ATTACK_TIME, 0.0, 1.0)
			position.y = _arena_base_y + FLY_HEIGHT * minf(1.0, _phase_t / 1.4) + 0.5 * sin(_t * 2.1)
			_visual.position.x = 0.12 * sin(_t * 50.0)
			for i in MAX_STARS:
				_stars[i].visible = (int(_t * 14.0) + i) % 4 != 0
			_layout_stars(1.0)
			if arena != null:
				arena.set_day_night((1.0 - cos(TAU * at)) * 0.5)   # 昼→夜→昼 整周期
			_dmg_t += delta
			while _dmg_t >= 0.1:
				_dmg_t -= 0.1
				if player != null and player.has_method("take_damage") and not _dead:
					player.take_damage(_aura_dmg)   # 普通 0.3/tick，随难度倍率提升
			if _phase_t >= ATTACK_TIME:
				_phase = 3
				_phase_t = 0.0
				_music_tail = 0.8   # 歌曲多播 0.8 秒后收尾
		3:
			# 落地复位
			position.y = lerpf(_arena_base_y + FLY_HEIGHT, _arena_base_y, clampf(_phase_t / LAND_TIME, 0.0, 1.0))
			_layout_stars(maxf(0.0, 1.0 - _phase_t / LAND_TIME))
			if _phase_t >= LAND_TIME:
				position.y = _arena_base_y
				_phase = 0
				_phase_t = 0.0
				_hide_stars()
				if arena != null:
					arena.set_day_night(0.0)
				_pick_wander_target()   # 释放完后随机移动最多 100 步


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


func _hide_stars() -> void:
	for st in _stars:
		st.visible = false


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
