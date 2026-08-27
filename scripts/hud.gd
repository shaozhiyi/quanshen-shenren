extends CanvasLayer
## 左上角 HUD：HealthBarX 血条（Godot 素材库，MIT 协议，纯矢量绘制）+ 玩家世界坐标显示。
## 血条监听 hp_changed 信号实时更新，血量低时自动变色（>70 绿、>10 橙、≤10 红）。

@export var bar_position := Vector2(24, 20)
@export var bar_size := Vector2(260, 28)
@export var coord_position := Vector2(24, 56)
@export var minimap_size := Vector2(160, 160)
@export var minimap_radius := 90.0
@export var minimap_position := Vector2(1280 - 24 - 160, 20)

const MAP_GRID := 60  # 采样网格（每刷新 3600 次高度采样，放大显示）

var _bar: Control
var _coord_label: Label
var _player: Node3D
var _ground: Node
var _map_bg: ColorRect
var _map_rect: TextureRect
var _map_tex: ImageTexture
var _last_map_pos := Vector3(1e9, 0, 0)
var _weapon_label: Label
var _inv_label: Label
var _hint_label: Label
var _charge_bar: Control
var _cross: Control
var _sword: Node
var _bow: Node
var _toast_text := ""
var _toast_t := 0.0


func _ready() -> void:
	layer = 10
	_player = get_node_or_null("../Player") as Node3D
	if _player == null:
		push_warning("HUD: 未找到 Player 节点")
		return

	var style := HealthBarXStyle.new()
	style.background_color = Color(0.10, 0.10, 0.13, 0.82)
	style.fill_color = Color(0.25, 0.72, 0.35, 1.0)
	style.use_threshold_colors = true
	style.threshold_red_max = 10.0
	style.threshold_orange_max = 70.0
	style.color_red = Color(0.90, 0.25, 0.20, 1.0)
	style.color_orange = Color(0.95, 0.60, 0.15, 1.0)
	style.color_green = Color(0.25, 0.72, 0.35, 1.0)
	style.border_enabled = true
	style.border_thickness = 2
	style.border_color = Color(0.45, 0.45, 0.50, 0.9)
	style.shadow_enabled = true
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_offset = Vector2(2, 3)
	style.shadow_apply_to = HealthBarXStyle.SHADOW_APPLY_BOTH
	style.label_enabled = true
	style.label_format = "{value}/{max}"
	style.label_custom_max = 100.0
	style.font_size = 16
	style.font_color = Color(1, 1, 1, 1)
	style.outline_size = 2
	style.outline_color = Color(0, 0, 0, 0.85)

	_bar = HealthBarXControl.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.style = style
	_bar.position = bar_position
	_bar.size = bar_size
	add_child(_bar)

	var max_hp: float = _player.get("max_hp") if _player.get("max_hp") != null else 100.0
	var hp: float = _player.get("hp") if _player.get("hp") != null else max_hp
	_bar.set_value(hp, false)

	_player.connect("hp_changed", _on_hp_changed)

	# 世界坐标显示（血条下方）
	_coord_label = Label.new()
	_coord_label.position = coord_position
	_coord_label.add_theme_font_size_override("font_size", 15)
	_coord_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_coord_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_coord_label.add_theme_constant_override("outline_size", 3)
	_coord_label.text = "X: 0.0  Y: 0.0  Z: 0.0"
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
	seed_label.text = "地形种子 %d（改 Ground.seed_value 可复现）" % tseed
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
	_weapon_label.text = "当前：剑（X 挥砍）｜Z 切换弓箭"
	add_child(_weapon_label)

	_inv_label = Label.new()
	_inv_label.position = bar_position + Vector2(0, 26)
	_inv_label.add_theme_font_size_override("font_size", 18)
	_inv_label.add_theme_color_override("font_color", Color(1, 0.88, 0.35))
	_inv_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_inv_label.add_theme_constant_override("outline_size", 4)
	_inv_label.text = "无敌"
	_inv_label.visible = false
	add_child(_inv_label)

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


func _add_tick(pos: Vector2, size: Vector2) -> void:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = Color(1, 1, 1, 0.85)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.add_child(r)


func _process(delta: float) -> void:
	if _player != null and _coord_label != null:
		var p := _player.global_position
		_coord_label.text = "X: %.1f  Y: %.1f  Z: %.1f" % [p.x, p.y, p.z]
		# 小地图仅在玩家移动≥6m时重采样（静止时零开销）
		if _ground != null and _ground.has_method("height_at_fast"):
			if _player.global_position.distance_squared_to(_last_map_pos) >= 36.0:
				_last_map_pos = _player.global_position
				_update_minimap()

	# 无敌：血条金色常显 + 倒计时标签
	if _player != null and _player.has_method("is_invincible") and _bar != null:
		var inv: bool = _player.call("is_invincible")
		if inv:
			_bar.modulate = Color(1.25, 1.08, 0.5)
			if _inv_label != null:
				_inv_label.visible = true
				_inv_label.text = "无敌 %.1fs" % float(_player.get("_invincible_t"))
		else:
			_bar.modulate = Color(1, 1, 1)
			if _inv_label != null:
				_inv_label.visible = false

	# 武器状态：提示文字 / 准星 / 蓄力条
	if _bow != null and _sword != null:
		var bow_on: bool = _bow.get("active")
		_cross.visible = bow_on
		if bow_on:
			_weapon_label.text = "当前：弓箭（按住左键蓄力 3 秒满，松手发射）｜Z 切换剑"
		else:
			_weapon_label.text = "当前：剑（X 挥砍）｜Z 切换弓箭"
		if _bow.call("is_charging"):
			_charge_bar.visible = true
			_charge_bar.call("set_value", _bow.call("charge_ratio") * 100.0, false)
		elif _bow.get("active") and _bow.get("_cooldown") > 0.0:
			# 射击冷却：红条倒数
			_charge_bar.visible = true
			_charge_bar.call("set_value", _bow.get("_cooldown") / 0.5 * 100.0, false)
		else:
			_charge_bar.visible = false

	# BOSS 空间交互提示 + 空间内隐藏小地图
	if _player != null and _player.has_method("in_arena"):
		var in_arena: bool = _player.call("in_arena")
		if _map_bg != null:
			_map_bg.visible = not in_arena
			_map_rect.visible = not in_arena
		var boss: Node = _player.call("current_boss") if _player.has_method("current_boss") else null
		if in_arena:
			_hint_label.visible = true
			var bname := "BOSS"
			if boss != null:
				bname = String(boss.get("boss_name"))
			if boss != null and boss.call("is_attacking"):
				_hint_label.text = "%s 腾空 · 日月倒悬 —— 持续失血！" % bname
				_hint_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3, 1))
			else:
				if boss != null:
					_hint_label.text = "—— %s 空间 · %s难度 ——（按 E 离开）" % [
						bname, String(boss.call("difficulty_name"))]
				else:
					_hint_label.text = "—— BOSS 空间 ——（按 E 离开）"
				_hint_label.add_theme_color_override("font_color", Color(1, 0.98, 0.8, 1))
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

	# toast 优先占用提示位（击杀奖励 / 难度切换 / 回收结果）
	if _toast_t > 0.0:
		_toast_t -= delta
		if _hint_label != null:
			_hint_label.visible = true
			_hint_label.text = _toast_text
			_hint_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35, 1))
		if _toast_t <= 0.0:
			_toast_t = 0.0


func toast(text: String) -> void:
	## 屏幕中下方金色提示，3 秒后自动交还给常规操作提示
	_toast_text = text
	_toast_t = 3.0


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


func _on_hp_changed(current: float, _maximum: float) -> void:
	if _bar != null:
		_bar.set_value(current, true)
