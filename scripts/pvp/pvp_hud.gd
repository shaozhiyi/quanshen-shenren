extends CanvasLayer
## PVP 精简 HUD：血条 / 蓝条 / 武器状态行 / 蓄力冷却条 / 击杀播报 / 计分板 + 背包。
## 武器状态文案与单机 HUD 同一套（直接问武器要最终值），单机的 BOSS/小地图/坐标都不需要。

const HealthBarX := preload("res://addons/health_bar_x/runtime/health_bar_x_control.gd")
const HealthBarXStyle := preload("res://addons/health_bar_x/runtime/health_bar_x_style.gd")
const INV_SCENE := preload("res://scripts/game_inventory.gd")

var player: Node
var inv: Node
var _hp_bar: Control
var _mp_bar: Control
var _weapon_label: Label
var _charge_bar: Control
var _charge_style: Resource
var _feed_lines: Array = []
var _feed_box: VBoxContainer
var _score_label: Label
var _dead_label: Label
const CHARGE_GOLD := Color(0.98, 0.75, 0.20, 1.0)
const CHARGE_SKILL := Color(0.62, 0.48, 0.98, 1.0)
const HP_LABEL_FMT := "{value}/{max}"


func _ready() -> void:
	layer = 10
	_build()


func bind(p: Node) -> void:
	player = p
	p.hp_changed.connect(_on_hp)
	p.mp_changed.connect(_on_mp)
	p.invincibility_changed.connect(_on_invincible)
	_on_hp(float(p.hp), float(p.max_hp))
	_on_mp(float(p.mp), float(p.max_mp))
	inv = get_node_or_null("Inventory")
	if inv != null and inv.has_method("setup_pvp"):
		inv.call("setup_pvp")


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var lv := Label.new()
	lv.name = "LvTag"
	lv.text = "PVP"
	lv.position = Vector2(16, 8)
	lv.add_theme_font_size_override("font_size", 26)
	lv.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	lv.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lv.add_theme_constant_override("outline_size", 6)
	root.add_child(lv)

	var hstyle := HealthBarXStyle.new()
	hstyle.label_format = HP_LABEL_FMT
	hstyle.label_enabled = true
	hstyle.use_threshold_colors = false
	_hp_bar = HealthBarX.new()
	_hp_bar.style = hstyle
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = PvpState.MAX_HP
	_hp_bar.position = Vector2(88, 12)
	_hp_bar.size = Vector2(300, 34)
	root.add_child(_hp_bar)

	var mstyle := HealthBarXStyle.new()
	mstyle.fill_color = Color(0.30, 0.55, 0.95)
	mstyle.label_enabled = true
	mstyle.label_format = "{value}/{max}"
	var mp_bar := HealthBarX.new()
	mp_bar.name = "MpBar"
	mp_bar.style = mstyle
	mp_bar.min_value = 0.0
	mp_bar.max_value = 200.0
	mp_bar.position = Vector2(88, 50)
	mp_bar.size = Vector2(240, 16)
	add_child(mp_bar)
	_mp_bar = mp_bar

	_weapon_label = Label.new()
	_weapon_label.position = Vector2(16, 92)
	_weapon_label.add_theme_font_size_override("font_size", 15)
	_weapon_label.add_theme_color_override("font_color", Color(1, 0.92, 0.65, 0.95))
	_weapon_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_weapon_label.add_theme_constant_override("outline_size", 3)
	_weapon_label.text = "当前：剑（X 挥砍）｜C 切换武器"
	root.add_child(_weapon_label)

	var cstyle := HealthBarXStyle.new()
	cstyle.background_color = Color(0.06, 0.06, 0.09, 0.75)
	cstyle.fill_color = CHARGE_GOLD
	cstyle.use_threshold_colors = false
	cstyle.border_enabled = true
	cstyle.border_thickness = 1
	cstyle.border_color = Color(0.5, 0.5, 0.55, 0.9)
	cstyle.label_enabled = false
	_charge_style = cstyle
	_charge_bar = HealthBarX.new()
	_charge_bar.min_value = 0.0
	_charge_bar.max_value = 100.0
	_charge_bar.style = cstyle
	_charge_bar.position = Vector2(640 - 130, 664)
	_charge_bar.size = Vector2(260, 16)
	_charge_bar.visible = false
	root.add_child(_charge_bar)

	_score_label = Label.new()
	_score_label.position = Vector2(0, 8)
	_score_label.size = Vector2(1280, 24)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 16)
	_score_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_score_label.add_theme_constant_override("outline_size", 5)
	root.add_child(_score_label)

	_dead_label = Label.new()
	_dead_label.position = Vector2(0, 300)
	_dead_label.size = Vector2(1280, 40)
	_dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead_label.add_theme_font_size_override("font_size", 30)
	_dead_label.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	_dead_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_dead_label.add_theme_constant_override("outline_size", 8)
	_dead_label.visible = false
	root.add_child(_dead_label)

	# 击杀/命中播报：血条右下开始的一列（与单机战斗播报同一口味）
	_feed_box = VBoxContainer.new()
	_feed_box.position = Vector2(400, 96)
	_feed_box.add_theme_constant_override("separation", 3)
	root.add_child(_feed_box)

	# 背包（Tab 开关；联机里开包不暂停整局，只禁自己操作）
	var inv_node := Control.new()
	inv_node.name = "Inventory"
	inv_node.set_script(INV_SCENE)
	add_child(inv_node)


## Tab 开背包由 game_inventory 自己处理（它 PROCESS_MODE_ALWAYS，暂停/联机都能收到）；
## 这里绝不要再处理一遍，否则一次 Tab 会开关两次等于没开。


func _on_hp(v: float, mx: float) -> void:
	if _hp_bar != null:
		_hp_bar.set_value(v, false)   # 量程就是 PvpState.MAX_HP，直接填当前血量
		if _hp_bar.style != null:
			_hp_bar.style.label_custom_max = mx
		_hp_bar.queue_redraw()
	if v <= 0.0 and player != null:
		_dead_label.visible = true
		_dead_label.text = "你被击倒了…%d 秒后重生" % int(ceil(PvpState.RESPAWN_WAIT))


func _on_mp(v: float, mx: float) -> void:
	if _mp_bar != null:
		_mp_bar.set_value(v / mx * 100.0, false)
		if _mp_bar.style != null:
			_mp_bar.style.label_custom_max = mx
		_mp_bar.queue_redraw()


func _on_invincible(active: bool, _dur: float) -> void:
	if _hp_bar != null and _hp_bar.style != null:
		_hp_bar.style.label_format = "永久" if active else HP_LABEL_FMT
		_hp_bar.queue_redraw()
	if _hp_bar != null and _hp_bar.style != null:
		_hp_bar.style.fill_color = Color(0.95, 0.8, 0.2) if active else Color(0.75, 0.2, 0.16)


## 命中播报：你使用剑劈砍击中玩家3
func announce_hit(weapon: String, target_name: String) -> void:
	_feed(str("你使用%s击中%s" % [weapon, target_name]), Color(1, 0.98, 0.8))


## 击杀播报 + 计分板刷新
func announce_kill(killer_name: String, victim_name: String) -> void:
	_feed(str("%s 击倒了 %s" % [killer_name, victim_name]), Color(1, 0.85, 0.35))


func announce(text: String, col := Color(1, 1, 1, 0.9)) -> void:
	_feed(text, col)


func set_scoreboard(lines: String) -> void:
	if _score_label != null:
		_score_label.text = lines


func clear_death_tag() -> void:
	_dead_label.visible = false


func _feed(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	_feed_box.add_child(l)
	_feed_lines.append(l)
	while _feed_lines.size() > 4:
		var old = _feed_lines.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var life := get_tree().create_timer(4.0)
	life.timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free()
		var idx := _feed_lines.find(l)
		if idx >= 0:
			_feed_lines.remove_at(idx))


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# 武器状态行 + 蓄力/冷却条：与单机同一套问法
	if _sword_ok():
		var staff_on: bool = bool(player.get("_staff").get("active")) if player.get("_staff") != null else false
		var bow_on: bool = bool(player.get("_bow").get("active"))
		var cur_w: Node = player.get("_staff") if staff_on else (player.get("_bow") if bow_on else player.get("_sword"))
		var lv: int = int(player.call("enhance_level_of", _cur_id(staff_on, bow_on)))
		var tag: String = "｜%s +%d" % [_enh_name(_cur_id(staff_on, bow_on)), lv] if lv > 0 else ""
		if staff_on:
			var sr: Array = cur_w.call("enhanced_range")
			var sb: Array = cur_w.call("blue_enhanced_range")
			_weapon_label.text = "当前：法杖 红%d/%d 蓝%d/%d（点按/蓄满 %.0f 秒，蓝带定身）%s%s%s｜C %s" % [
				int(sr[0]), int(sr[1]), int(sb[0]), int(sb[1]), float(cur_w.call("charge_time")),
				tag, _skill_text(cur_w, false), _skill_text(cur_w, true), _nxt()]
		elif bow_on:
			var dr: Array = cur_w.call("enhanced_range")
			_weapon_label.text = "当前：弓箭 攻击 %d~%d（按住左键 / X 蓄力 %.0f 秒满，松手发射）%s%s%s｜C %s" % [
				int(dr[0]), int(dr[1]), float(cur_w.call("charge_time")),
				tag, _skill_text(cur_w, false), _skill_text(cur_w, true), _nxt()]
		else:
			_weapon_label.text = "当前：剑 攻击 %d（X 挥砍）%s%s%s｜C %s" % [
				int(player.call("sword_damage")), tag,
				_skill_text(cur_w, false), _skill_text(cur_w, true), _nxt()]
		var act: Node = player.get("_staff") if staff_on else player.get("_bow")
		var bar_val := -1.0
		var bar_skill := false
		if (staff_on or bow_on) and bool(act.call("is_charging")):
			bar_val = float(act.call("charge_ratio")) * 100.0
		if bar_val < 0.0 and cur_w.has_method("skill_cooldown_left"):
			var s1: float = float(cur_w.call("skill_cooldown_left"))
			if s1 > 0.0:
				bar_val = s1 / maxf(float(cur_w.call("skill_cooldown")), 0.001) * 100.0
				bar_skill = true
		if bar_val < 0.0 and cur_w.has_method("skill2_cooldown_left"):
			var s2: float = float(cur_w.call("skill2_cooldown_left"))
			if s2 > 0.0:
				bar_val = s2 / maxf(float(cur_w.call("skill2_cooldown")), 0.001) * 100.0
				bar_skill = true
		if bar_val < 0.0 and (staff_on or bow_on):
			var cl: float = float(act.call("cooldown_left"))
			if cl > 0.0:
				bar_val = cl / maxf(float(act.call("shot_cooldown")), 0.001) * 100.0
		if bar_val >= 0.0:
			_charge_bar.visible = true
			var want_col: Color = CHARGE_SKILL if bar_skill else CHARGE_GOLD
			if _charge_style.fill_color != want_col:
				_charge_style.fill_color = want_col
			_charge_bar.call("set_value", bar_val, false)
		else:
			_charge_bar.visible = false


func _sword_ok() -> bool:
	return player.get("_sword") != null and player.get("_bow") != null


func _cur_id(staff_on: bool, bow_on: bool) -> String:
	return "staff" if staff_on else ("bow" if bow_on else "sword")


func _enh_name(id: String) -> String:
	match id:
		"sword": return "剑"
		"bow": return "弓箭"
		"staff": return "法杖"
	return id


func _nxt() -> String:
	if int(player.call("equipped_count")) < 2:
		return "（只装备了一把）"
	var i := int(player.call("next_weapon_index"))
	return "切换%s" % _enh_name(String(player.call("weapon_id_at", i)))


func _skill_text(w: Node, two := false) -> String:
	if w == null:
		return ""
	var nm: String
	var cl: float
	var cost: int
	var ok: bool
	var desc: String
	if two:
		if not w.has_method("skill2_name"):
			return ""
		nm = String(w.call("skill2_name"))
		cl = float(w.call("skill2_cooldown_left"))
		cost = int(w.call("skill2_cost"))
		ok = bool(w.call("skill2_ready"))
		desc = String(w.call("skill2_desc"))
	else:
		if not w.has_method("skill_name"):
			return ""
		nm = String(w.call("skill_name"))
		cl = float(w.call("skill_cooldown_left"))
		cost = int(w.call("skill_cost"))
		ok = bool(w.call("skill_ready"))
		desc = String(w.call("skill_desc"))
	var key := "2" if two else "1"
	if cl > 0.0:
		return "｜%s%s 冷却%.1f秒" % [key, nm, cl]
	if not ok:
		return "｜%s%s 缺蓝%d" % [key, nm, cost]
	return "｜%s %s %s" % [key, nm, desc]
