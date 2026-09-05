extends CanvasLayer
## 左上角 HUD：等级徽章 + 血条（红）+ 魔法条（蓝）+ 经验条（绿）+ 坐标（世界/战斗两套）+ 小地图。
## 条控件用 HealthBarX（Godot 素材库，MIT 协议，纯矢量绘制）。
## 血条监听 hp_changed 实时更新；无敌期把血条整体染成金色（与普通红血区分）。
## 魔法上限 200 是给之后的技能系统预留的；经验条本版不涨（升级系统未做）。

@export var bar_position := Vector2(86, 20)
@export var bar_size := Vector2(238, 28)
@export var coord_position := Vector2(24, 92)
@export var minimap_size := Vector2(160, 160)
@export var minimap_radius := 90.0
@export var minimap_position := Vector2(1280 - 24 - 160, 20)

# ---- 播报提示（击中 / 击败）：下面这些数字与文案都可以直接改 ----
@export var feed_max := 4                        # 最多同时几条，超了就删最末尾（最旧）那条
@export var feed_line_width := 150.0             # 每条长度：血条 238 的一半多一点
@export var feed_line_height := 24.0             # 每条高度：4 条 + 间距正好铺到"C 切换弓箭"那一行
@export var feed_gap := 4.0                      # 条与条的间距
@export var feed_start_offset := Vector2(12, 0)  # 起点 = 血条右上角 + 这个偏移
@export var feed_font_size := 15
@export var feed_life := 0.0                     # 每条停留秒数；0 = 不自动消失，只按条数淘汰
@export var feed_announce_hits := true           # 每次击中是否也播一条（只要击杀可改成 false）
@export var feed_newest_on_top := true           # 新提示出现在最上面（下面那条就是最旧的，先被挤掉）
@export var feed_fmt_hit := "你使用%s击中%s"      # 击中单位：武器、单位
@export var feed_fmt_kill := "你使用%s击败了%s"   # 击败普通单位：武器、单位
@export var feed_fmt_boss_kill := "你击败了%s"    # 击杀 BOSS：单位

const MAP_GRID := 60  # 采样网格（每刷新 3600 次高度采样，放大显示）

# 血条三档（普通红 / 过渡橙红 / 濒危暗红）与无敌金条
const HP_FILL := Color(0.86, 0.24, 0.22)
const HP_MID := Color(0.93, 0.44, 0.16)
const HP_LOW := Color(0.63, 0.06, 0.07)
const HP_GOLD := Color(0.95, 0.78, 0.28)
const MP_FILL := Color(0.26, 0.52, 0.95)
const EXP_FILL := Color(0.30, 0.82, 0.36)

var _bar: Control
var _mp_bar: Control
var _exp_bar: Control
var _lv_label: Label
var _coord_label: Label
var _player: Node3D
var _ground: Node
var _map_bg: ColorRect
var _map_rect: TextureRect
var _map_tex: ImageTexture
var _last_map_pos := Vector3(1e9, 0, 0)
var _weapon_label: Label
var _hint_label: Label
const HP_LABEL_FMT := "{value}/{max}"      # 血条数字格式（无敌时临时换成"永久"）
var _charge_bar: Control
var _cross: Control
var _sword: Node
var _bow: Node
var _mp_shown := -1.0
var _mp_max_shown := -1.0
var _exp_shown := -1.0
var _lv_shown := -1
var _inv_bar_golden := false
var _feed: Control                       # 播报容器（血条右侧）
var _feed_lines: Array = []              # 从上到下 = 从新到旧，每项 {label: Label, age: float}


func _ready() -> void:
	layer = 10
	_player = get_node_or_null("../Player") as Node3D
	if _player == null:
		push_warning("HUD: 未找到 Player 节点")
		return

	# ---- 等级徽章（贴在血条左侧）----
	_lv_label = Label.new()
	_lv_label.position = Vector2(bar_position.x - 62, bar_position.y - 1)
	_lv_label.size = Vector2(58, 30)
	_lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lv_label.add_theme_font_size_override("font_size", 24)
	_lv_label.add_theme_color_override("font_color", Color(1, 0.94, 0.72, 1))
	_lv_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_lv_label.add_theme_constant_override("outline_size", 5)
	_lv_label.text = "LV1"
	add_child(_lv_label)

	# ---- 血条（红）----
	_bar = _make_bar(bar_position, bar_size, HP_FILL, true, HP_LABEL_FMT, 16, 100.0)
	_set_hp_palette(false)
	var max_hp: float = _player.get("max_hp") if _player.get("max_hp") != null else 100.0
	var hp: float = _player.get("hp") if _player.get("hp") != null else max_hp
	_bar.set_value(hp / max_hp * 100.0, false)
	_player.connect("hp_changed", _on_hp_changed)

	# ---- 魔法条（蓝，上限 200）----
	# 注意：HealthBarX 是"百分比"条——set_value 会把值归一成 0..100 存，
	# 画填充时又除以 max_value。所以条量程必须恒为 100、传百分比进去；
	# 真实上限 200 只交给 style.label_custom_max 换算显示文字（否则满值只画一半）。
	var mp_max: float = float(_player.get("max_mp")) if _player.get("max_mp") != null else 200.0
	var mp_now: float = float(_player.get("mp")) if _player.get("mp") != null else mp_max
	_mp_bar = _make_bar(Vector2(bar_position.x, bar_position.y + 32), Vector2(bar_size.x, 16),
		MP_FILL, false, "{value}/{max}", 11, mp_max)
	_mp_bar.set_value(mp_now / mp_max * 100.0, false)
	_mp_shown = mp_now
	_mp_max_shown = mp_max

	# ---- 经验条（绿，细）：升级系统未做，本版恒为 0 ----
	_exp_bar = _make_bar(Vector2(bar_position.x, bar_position.y + 52), Vector2(bar_size.x, 8),
		EXP_FILL, false, "", 10, 1.0)
	_exp_bar.set_value(_exp_ratio() * 100.0, false)
	_exp_shown = _exp_ratio()

	# 坐标显示（状态区下方）：大地图报世界坐标，进 BOSS 空间改报战斗坐标
	_coord_label = Label.new()
	_coord_label.position = coord_position
	_coord_label.add_theme_font_size_override("font_size", 15)
	_coord_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_coord_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_coord_label.add_theme_constant_override("outline_size", 3)
	_coord_label.text = "世界 X: 0.0  Y: 0.0  Z: 0.0"
	add_child(_coord_label)

	# 本局地形种子（同一种子 = 同一片地形与石头分布，可复现/分享）
	var seed_label := Label.new()
	seed_label.position = Vector2(24, 692)
	seed_label.add_theme_font_size_override("font_size", 13)
	seed_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	seed_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	seed_label.add_theme_constant_override("outline_size", 3)
	var gnd := get_node_or_null("../Ground")
	var tseed: int = int(gnd.get("terrain_seed")) if gnd != null else 0
	seed_label.text = "地形种子 %d ｜ F5 存档（save/*.json）" % tseed
	add_child(seed_label)

	# 右上角地形小地图：按海拔着色显示周围地形（深=低，浅=高），白点=玩家
	_ground = get_node_or_null("../Ground")
	_map_bg = ColorRect.new()
	_map_bg.position = minimap_position - Vector2(3, 3)
	_map_bg.size = minimap_size + Vector2(6, 6)
	_map_bg.color = Color(0, 0, 0, 0.6)
	add_child(_map_bg)
	_map_rect = TextureRect.new()
	_map_rect.position = minimap_position
	_map_rect.size = minimap_size
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_rect)
	_update_minimap()

	# ---- 武器 UI：提示文字 / 蓄力条 / 准星 ----
	_sword = get_node_or_null("../Player/Camera3D/Sword")
	_bow = get_node_or_null("../Player/Camera3D/Bow")

	_weapon_label = Label.new()
	_weapon_label.position = coord_position + Vector2(0, 24)
	_weapon_label.add_theme_font_size_override("font_size", 15)
	_weapon_label.add_theme_color_override("font_color", Color(1, 0.92, 0.65, 0.95))
	_weapon_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_weapon_label.add_theme_constant_override("outline_size", 3)
	_weapon_label.text = "当前：剑（X 挥砍）｜C 切换弓箭"
	add_child(_weapon_label)

	_hint_label = Label.new()
	_hint_label.position = Vector2(640 - 240, 610)
	_hint_label.size = Vector2(480, 26)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 19)
	_hint_label.add_theme_color_override("font_color", Color(1, 0.98, 0.8, 1))
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint_label.add_theme_constant_override("outline_size", 4)
	_hint_label.visible = false
	add_child(_hint_label)

	var cstyle := HealthBarXStyle.new()
	cstyle.background_color = Color(0.06, 0.06, 0.09, 0.75)
	cstyle.fill_color = Color(0.98, 0.75, 0.20, 1.0)
	cstyle.use_threshold_colors = false
	cstyle.border_enabled = true
	cstyle.border_thickness = 1
	cstyle.border_color = Color(0.5, 0.5, 0.55, 0.9)
	cstyle.shadow_enabled = false
	cstyle.label_enabled = false
	_charge_bar = HealthBarXControl.new()
	_charge_bar.min_value = 0.0
	_charge_bar.max_value = 100.0
	_charge_bar.style = cstyle
	_charge_bar.position = Vector2(640 - 130, 664)
	_charge_bar.size = Vector2(260, 16)
	_charge_bar.visible = false
	add_child(_charge_bar)

	_cross = Control.new()
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.visible = false
	add_child(_cross)
	_add_tick(Vector2(-15, -1), Vector2(9, 2))
	_add_tick(Vector2(6, -1), Vector2(9, 2))
	_add_tick(Vector2(-1, -15), Vector2(2, 9))
	_add_tick(Vector2(-1, 6), Vector2(2, 9))
	_add_tick(Vector2(-2, -2), Vector2(4, 4))

	_build_feed()
	_bind_feed_targets()


# ---- 播报提示：血条右侧最多 feed_max 条，新条目挤进来就把最末尾（最旧）那条删掉 ----

func _build_feed() -> void:
	_feed = Control.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.position = bar_position + feed_start_offset + Vector2(bar_size.x, 0)
	add_child(_feed)


func _bind_feed_targets() -> void:
	## 按分组找实体（层级一改 ../ 路径就静默取 null，见项目惯例）；
	## BOSS 由 BossField 生成、比 HUD 早进树，所以这里一次绑完就够了
	for b in get_tree().get_nodes_in_group("boss_unit"):
		if b.has_signal("damaged") and not b.damaged.is_connected(_on_unit_damaged):
			b.damaged.connect(_on_unit_damaged.bind(b))
		if b.has_signal("died") and not b.died.is_connected(_on_unit_died):
			b.died.connect(_on_unit_died)


func announce(text: String, col: Color) -> void:
	## 播一条提示。文案自己拼（见 _on_unit_damaged / _on_unit_died）
	if _feed == null or text == "":
		return
	var l := Label.new()
	l.text = text
	l.size = Vector2(feed_line_width, feed_line_height)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", feed_font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 3)
	# 单位名再长也只省略号收尾，不许压到右边的小地图
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_feed.add_child(l)
	_feed_lines.insert(0, {"label": l, "age": 0.0})
	while _feed_lines.size() > feed_max:
		_drop_line(_feed_lines.size() - 1)
	_layout_feed()


func _drop_line(i: int) -> void:
	if i < 0 or i >= _feed_lines.size():
		return
	var item: Dictionary = _feed_lines[i]
	_feed_lines.remove_at(i)
	var l: Label = item.get("label")
	if l != null and is_instance_valid(l):
		l.queue_free()


func _layout_feed() -> void:
	var step := feed_line_height + feed_gap
	for i in _feed_lines.size():
		var row := i if feed_newest_on_top else _feed_lines.size() - 1 - i
		(_feed_lines[i].get("label") as Control).position = Vector2(0, float(row) * step)


func _on_unit_damaged(weapon: String, _amount: int, unit: Node) -> void:
	if not feed_announce_hits:
		return
	announce(feed_fmt_hit % [weapon, _unit_name(unit)], Color(1, 0.98, 0.86, 0.95))


func _on_unit_died(unit: Node) -> void:
	var nm := _unit_name(unit)
	## 击杀 BOSS 只报"你击败了yy"；将来若有普通杂兵，报"你使用xx击败了yy"
	if unit != null and unit.is_in_group("boss_unit"):
		announce(feed_fmt_boss_kill % nm, Color(1, 0.84, 0.35, 1))
	else:
		var w := "弓"
		if unit != null:
			w = String(unit.get("last_weapon"))
		announce(feed_fmt_kill % [w, nm], Color(1, 0.84, 0.35, 1))


func _unit_name(unit: Node) -> String:
	if unit == null or not is_instance_valid(unit):
		return "目标"
	var nm := String(unit.get("boss_name"))
	return nm if nm != "" else String(unit.name)


func _feed_tick(delta: float) -> void:
	## feed_life = 0 表示不自动消失，只按条数淘汰
	if feed_life <= 0.0:
		return
	var i := _feed_lines.size() - 1
	while i >= 0:
		_feed_lines[i].age = float(_feed_lines[i].age) + delta
		if float(_feed_lines[i].age) > feed_life:
			_drop_line(i)
		i -= 1
	_layout_feed()


func _make_bar(pos: Vector2, size: Vector2, fill: Color, thresholds: bool,
		fmt: String, fsize: int, label_max: float) -> Control:
	## 统一风格的状态条：深色底 + 细边框 + 可选数字；thresholds=true 时按三档换色
	## label_max：文字里 "{max}" 显示的真实上限（填充量程恒为 100，见下方注释）
	var st := HealthBarXStyle.new()
	st.background_color = Color(0.10, 0.10, 0.13, 0.82)
	st.fill_color = fill
	st.use_threshold_colors = thresholds
	st.threshold_red_max = 10.0
	st.threshold_orange_max = 70.0
	st.color_red = HP_LOW
	st.color_orange = HP_MID
	st.color_green = HP_FILL
	st.border_enabled = true
	st.border_thickness = 2
	st.border_color = Color(0.45, 0.45, 0.50, 0.9)
	st.shadow_enabled = true
	st.shadow_color = Color(0, 0, 0, 0.4)
	st.shadow_offset = Vector2(2, 3)
	st.shadow_apply_to = HealthBarXStyle.SHADOW_APPLY_BOTH
	st.label_enabled = fmt != ""
	st.label_format = fmt
	st.label_custom_max = label_max
	st.font_size = fsize
	st.font_color = Color(1, 1, 1, 1)
	st.outline_size = 2
	st.outline_color = Color(0, 0, 0, 0.85)
	var bar := HealthBarXControl.new()
	# 先去掉控件自带的 120×24 最小尺寸，再定位/给尺寸；
	# 顺序反了会被最小高度夹住（细条变粗、三条叠在一起），后改也回缩不了
	bar.custom_minimum_size = Vector2.ZERO
	bar.min_value = 0.0
	# 插件是"百分比"条：set_value 归一成 0..100 存、画填充时除以 max_value，
	# 所以量程恒为 100（真实上限走 label_custom_max 换算文字，别把它放进 max_value）
	bar.max_value = 100.0
	bar.style = st
	bar.position = pos
	bar.size = size
	add_child(bar)
	return bar


func _set_hp_palette(golden: bool) -> void:
	## 血条配色：平时红色系（越低越暗），无敌期整体换成金色
	## （旧版靠 modulate 染金，血条改红后 modulate 会把红压成暗橙，所以改成直接换色）
	if _bar == null or _bar.style == null:
		return
	var s = _bar.style
	if golden == _inv_bar_golden:
		return
	_inv_bar_golden = golden
	var base := HP_GOLD if golden else HP_FILL
	var mid := HP_GOLD.lightened(0.18) if golden else HP_MID
	var low := HP_GOLD.darkened(0.25) if golden else HP_LOW
	s.fill_color = base
	s.color_green = base
	s.color_orange = mid
	s.color_red = low
	_bar.queue_redraw()


func _exp_ratio() -> float:
	## 经验条比例 0..1（升级系统未实现，玩家侧恒为 0；接口留好，之后加了自动就显示）
	if _player != null and _player.has_method("exp_ratio"):
		return clampf(float(_player.call("exp_ratio")), 0.0, 1.0)
	return 0.0


func _add_tick(pos: Vector2, size: Vector2) -> void:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = Color(1, 1, 1, 0.85)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.add_child(r)


func _enh_lv(id: String) -> int:
	## 某件装备的强化等级（玩家未就绪/无方法时按 0）
	if _player != null and _player.has_method("enhance_level_of"):
		return int(_player.call("enhance_level_of", id))
	return 0


func _sword_power() -> int:
	## 剑的最终攻击力：向玩家要（含指数强化与向下取整），玩家未就绪时退回基础值
	if _player != null and _player.has_method("sword_damage"):
		return int(_player.call("sword_damage"))
	return 50


func _enh_name(id: String) -> String:
	var inv := get_node_or_null("Inventory")
	if inv != null and inv.has_method("item_name"):
		return String(inv.call("item_name", id))
	match id:
		"sword": return "剑"
		"bow": return "弓箭"
		"armor": return "防具"
	return id


## 坐标显示约定：X = 横轴、Y = 纵轴（前后方向）、Z = 高度。
## 引擎内部是 X/Z 水平 + Y 竖直，这里只换"给人看"的顺序（把高度放到第三个数），
## 存档、小地图、物理一律仍按引擎轴，别跟着换。
func _coord_text(v: Vector3) -> String:
	return "X: %.1f  Y: %.1f  Z: %.1f" % [v.x, v.z, v.y]


func _process(delta: float) -> void:
	_feed_tick(delta)
	if _player != null and _coord_label != null:
		# 战斗空间在世界里偏出去几千米，所以战斗内报"战斗坐标"（开战那一刻 = 0,0,0），
		# 大地图才报世界坐标；前缀写出来，免得两种数混在一起看不懂
		var battle := false
		if _player.has_method("coords_are_battle"):
			battle = bool(_player.call("coords_are_battle"))
		var p: Vector3 = _player.call("display_coords") \
			if _player.has_method("display_coords") else _player.global_position
		_coord_label.text = "%s %s" % ["战斗" if battle else "世界", _coord_text(p)]
		# 小地图仅在玩家移动≥6m时重采样（静止时零开销）
		if _ground != null and _ground.has_method("height_at_fast"):
			if _player.global_position.distance_squared_to(_last_map_pos) >= 36.0:
				_last_map_pos = _player.global_position
				_update_minimap()

	# 无敌：血条整体换成金色并把数字换成"永久"（时长仍是 10 秒，不另开倒计时文字）
	if _player != null and _player.has_method("is_invincible") and _bar != null:
		var inv: bool = _player.call("is_invincible")
		var want_fmt := "永久" if inv else HP_LABEL_FMT
		if _bar.style != null and String(_bar.style.label_format) != want_fmt:
			_bar.style.label_format = want_fmt
			_bar.queue_redraw()
		_set_hp_palette(inv)

	# 魔法条 / 经验条 / 等级：值变了才重绘（静止时零开销）
	if _player != null and _mp_bar != null:
		var mp: float = float(_player.get("mp")) if _player.get("mp") != null else 0.0
		var mmax: float = float(_player.get("max_mp")) if _player.get("max_mp") != null else 200.0
		if absf(mp - _mp_shown) > 0.001 or absf(mmax - _mp_max_shown) > 0.001:
			_mp_shown = mp
			_mp_max_shown = mmax
			if _mp_bar.style != null:
				_mp_bar.style.label_custom_max = mmax   # 真实上限只用于文字
			_mp_bar.set_value(mp / mmax * 100.0, false)  # 填充量程恒为 100
		var er := _exp_ratio()
		if absf(er - _exp_shown) > 0.001:
			_exp_shown = er
			_exp_bar.set_value(er * 100.0, false)
		if _lv_label != null:
			var lv: int = int(_player.get("level")) if _player.get("level") != null else 1
			if lv != _lv_shown:
				_lv_shown = lv
				_lv_label.text = "LV%d" % lv

	# 武器状态：提示文字 / 准星 / 蓄力条
	if _bow != null and _sword != null:
		var bow_on: bool = _bow.get("active")
		_cross.visible = bow_on
		var cur := "bow" if bow_on else "sword"
		var lv := _enh_lv(cur)
		var armor_lv := _enh_lv("armor")
		var tag := "｜%s +%d" % [String(_enh_name(cur)), lv] if lv > 0 else ""
		if armor_lv > 0:
			tag += "｜甲 +%d" % armor_lv
		# 数值一律向武器脚本要最终值（含强化倍率 + 向下取整），改算法不用回来动 HUD
		var ct: float = float(_bow.call("charge_time"))
		if bow_on:
			var dr: Array = _bow.call("enhanced_range")
			_weapon_label.text = "当前：弓箭 攻击 %d~%d（按住左键 / X 蓄力 %.0f 秒满，松手发射）｜C 切换剑%s" % [
				int(dr[0]), int(dr[1]), ct, tag]
		else:
			_weapon_label.text = "当前：剑 攻击 %d（X 挥砍）｜C 切换弓箭%s" % [_sword_power(), tag]
		if _bow.call("is_charging"):
			_charge_bar.visible = true
			_charge_bar.call("set_value", _bow.call("charge_ratio") * 100.0, false)
		elif _bow.get("active") and _bow.get("_cooldown") > 0.0:
			# 射击冷却：红条倒数
			_charge_bar.visible = true
			_charge_bar.call("set_value", _bow.get("_cooldown") / float(_bow.call("shot_cooldown")) * 100.0, false)
		else:
			_charge_bar.visible = false

	# BOSS 空间交互提示 + 空间内隐藏小地图（只保留按键指引，出招过程不再刷屏）
	if _player != null and _player.has_method("in_arena"):
		var in_arena: bool = _player.call("in_arena")
		if _map_bg != null:
			_map_bg.visible = not in_arena
			_map_rect.visible = not in_arena
		var boss: Node = _player.call("current_boss") if _player.has_method("current_boss") else null
		if in_arena:
			_hint_label.visible = true
			_hint_label.add_theme_color_override("font_color", Color(1, 0.98, 0.8, 1))
			if boss != null:
				_hint_label.text = "—— %s 空间 · %s难度 ——（按 E 离开）" % [
					String(boss.get("boss_name")), String(boss.call("difficulty_name"))]
			else:
				_hint_label.text = "—— BOSS 空间 ——（按 E 离开）"
		elif _player.call("near_boss") and boss != null:
			_hint_label.visible = true
			_hint_label.add_theme_color_override("font_color", Color(1, 0.98, 0.8, 1))
			if boss.call("can_adjust_difficulty"):
				_hint_label.text = "%s · %s难度（HP %d）—— 按 E 开战 ｜ R 切换难度" % [
					String(boss.get("boss_name")), String(boss.call("difficulty_name")), int(boss.get("max_hp"))]
			else:
				_hint_label.text = "靠近 %s —— 按 E 挑战（先赢一次才能切换难度）" % String(boss.get("boss_name"))
		else:
			_hint_label.visible = false


func _update_minimap() -> void:
	## 采样周围地形高度，绘制成深-浅高度图（60x60 采样后放大），白色十字为玩家位置
	## 每次重建 60x60 源图（resize 会就地改尺寸，复用旧图会只刷新左上角）
	var p := _player.global_position
	var cell := minimap_radius * 2.0 / float(MAP_GRID)
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(MAP_GRID * MAP_GRID)
	var hmin := 1e9
	var hmax := -1e9
	for y in MAP_GRID:
		for x in MAP_GRID:
			var wx := p.x - minimap_radius + (x + 0.5) * cell
			var wz := p.z - minimap_radius + (y + 0.5) * cell
			var hv: float = _ground.height_at_fast(wx, wz)
			heights[y * MAP_GRID + x] = hv
			if hv < hmin:
				hmin = hv
			if hv > hmax:
				hmax = hv
	var img := Image.create(MAP_GRID, MAP_GRID, false, Image.FORMAT_RGB8)
	var span := maxf(hmax - hmin, 0.01)
	for y in MAP_GRID:
		for x in MAP_GRID:
			var t := (heights[y * MAP_GRID + x] - hmin) / span
			# 低谷深绿 → 山脊浅黄
			var col := Color(0.14 + 0.38 * t, 0.26 + 0.38 * t, 0.10 + 0.22 * t)
			img.set_pixel(x, y, col)
	img.resize(int(minimap_size.x), int(minimap_size.y), Image.INTERPOLATE_NEAREST)
	# 玩家标记（白点，放大后画在中心）
	var cx := int(minimap_size.x * 0.5)
	var cy := int(minimap_size.y * 0.5)
	for dy in 3:
		for dx in 3:
			img.set_pixel(cx - 1 + dx, cy - 1 + dy, Color.WHITE)
	if _map_tex == null:
		_map_tex = ImageTexture.create_from_image(img)
		_map_rect.texture = _map_tex
	else:
		_map_tex.update(img)


func _on_hp_changed(current: float, maximum: float) -> void:
	# 填充量程恒为 100，传百分比（文字上限走 label_custom_max）
	if _bar != null:
		_bar.set_value(current / maxf(maximum, 0.001) * 100.0, true)
