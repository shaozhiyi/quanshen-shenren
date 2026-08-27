extends Control
## 背包 & 装备栏（Tab 开关）。
## 数据层复用 Godot 素材库插件 addons/grid_inventory（MIT, GodotForge）的
## Inventory / InvItem 类；物品图标取自 game-icons.net（CC-BY 4.0，见 assets/items/CREDITS.txt）。
## 装备栏：武器 / 副武器 / 防具；背包 3 行 × 9 列。默认装备剑+弓箭+防具（防具自动穿戴）。
## 交互：拖拽穿卸；单击选中、双击使用（消耗品生效 / 装备穿戴）；选中后按 E 丢弃→地上生成箱子。

const BAG_SIZE := 27
const BAG_COLS := 9
const SLOT_PX := 58.0
const GAP := 6.0

const K_BAG := 0
const K_WEAPON := 1
const K_SUB := 2
const K_ARMOR := 3

# id -> 定义：名称/可装备去处(-1=不可装备)/图标/着色/属性说明/[use]
const DB := {
	"sword":  {"name": "剑", "slot": K_WEAPON, "icon": "res://assets/items/sword.svg", "tint": Color(0.88, 0.92, 0.98),
		"desc": "主武器 · 攻击力 +50\n按 X 挥砍，命中即扣 50"},
	"bow":    {"name": "弓箭", "slot": K_SUB, "icon": "res://assets/items/bow.svg", "tint": Color(0.95, 0.80, 0.62),
		"desc": "副武器 · 攻击力 12~50\n按住左键蓄力 3 秒满，满蓄扣 50\n弹道射程由物理引擎决定，每箭冷却 0.5 秒"},
	"armor":  {"name": "防具", "slot": K_ARMOR, "icon": "res://assets/items/armor.svg", "tint": Color(1.00, 0.85, 0.40),
		"desc": "护甲 · 受到的所有伤害减半\nBOSS 光环 3 血/秒 → 1.5 血/秒"},
	"dogmilk": {"name": "野生狗奶", "slot": -1, "icon": "res://assets/items/dogmilk.png", "tint": Color(1, 1, 1),
		"desc": "消耗品 · 双击饮用\n获得 10 秒无敌（免疫伤害），血条常显\n10 秒后解除并恢复满血",
		"use": "invincible", "dur": 10.0},
}

var _bag: Inventory                 # addons/grid_inventory 的数据模型（27 格）
var _items := {}                    # id -> InvItem
var _eq := {"weapon": "sword", "subweapon": "bow", "armor": "armor"}
var _eq_slots := {}                 # key -> SlotCtl
var _bag_slots: Array = []
var _player: Node
var _open := false
var _selected_loc: Array = []       # 当前选中的槽位 ["bag",i]/["eq",k]
var _hint_label: Label
var _hint_default := ""
var _hint_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_player = get_node_or_null("../../Player")
	_build_items()
	_build_bag()
	_build_ui()
	refresh_all()
	_sync_player()


# ---- 数据 ----
func _build_items() -> void:
	for id in DB:
		var it := InvItem.new()
		it.id = StringName(id)
		it.name = DB[id]["name"]
		it.icon = load(DB[id]["icon"])
		it.color = DB[id]["tint"]
		_items[id] = it


func _build_bag() -> void:
	_bag = Inventory.new(BAG_SIZE)
	# 防具自动穿戴（_eq.armor 默认已为 armor），背包起始留空


func item_name(id: String) -> String:
	return String(DB[id]["name"]) if DB.has(id) else id


## 对外：加入物品（可指定数量）。可装备且对应栏空→自动穿戴；否则进背包。
## 返回是否全部放下：部分放下时已放的保留，返回值 false 供调用方提示"背包已满"。
func add_item(id: String, count: int = 1) -> bool:
	if not DB.has(id) or count <= 0:
		return false
	var placed := 0
	var slot := int(DB[id]["slot"])
	for _i in count:
		# 仅首件走"自动穿戴"逻辑，其余进背包
		if slot >= 0 and placed == 0:
			var key := _kind_to_key(slot)
			if key != "" and _eq[key] == "":
				_eq[key] = id
				placed += 1
				continue
		var idx := _first_empty_bag()
		if idx < 0:
			break
		bag_set(idx, id)
		placed += 1
	refresh_all()
	if placed > 0:
		_sync_player()
	return placed >= count


## 统计某 id 在背包+装备栏的总数量
func count_of(id: String) -> int:
	var n := 0
	for i in BAG_SIZE:
		if bag_get(i) == id:
			n += 1
	for k in _eq:
		if _eq[k] == id:
			n += 1
	return n


func _first_empty_bag() -> int:
	for i in BAG_SIZE:
		if bag_get(i) == "":
			return i
	return -1


func _kind_to_key(kind: int) -> String:
	match kind:
		K_WEAPON: return "weapon"
		K_SUB: return "subweapon"
		K_ARMOR: return "armor"
	return ""


func bag_get(i: int) -> String:
	var s = _bag.slots[i]
	return String(s.item.id) if s != null else ""


func bag_set(i: int, id: String) -> void:
	_bag.slots[i] = ({"item": _items[id]} if id != "" else null)


func eq_get(k: String) -> String:
	return _eq[k]


func eq_set(k: String, id: String) -> void:
	_eq[k] = id


func key_kind(k: String) -> int:
	match k:
		"weapon": return K_WEAPON
		"subweapon": return K_SUB
		"armor": return K_ARMOR
	return -1


## 统一搬移：src/dst = ["bag", idx] 或 ["eq", key]；类型不符返回 false
func move_item(src: Array, dst: Array) -> bool:
	if src[0] == dst[0] and int(src[1]) == int(dst[1]):
		return false
	var sid := _get_at(src)
	var did := _get_at(dst)
	if dst[0] == "eq" and sid != "" and int(DB[sid]["slot"]) != key_kind(dst[1]):
		return false
	if src[0] == "eq" and did != "" and int(DB[did]["slot"]) != key_kind(src[1]):
		return false
	_set_at(dst, sid)
	_set_at(src, did)
	refresh_all()
	_sync_player()
	return true


func _get_at(loc: Array) -> String:
	return bag_get(loc[1]) if loc[0] == "bag" else eq_get(loc[1])


func _set_at(loc: Array, id: String) -> void:
	if loc[0] == "bag":
		bag_set(loc[1], id)
	else:
		eq_set(loc[1], id)


func _sync_player() -> void:
	if _player != null and _player.has_method("set_equipment"):
		_player.call("set_equipment", _eq.weapon, _eq.subweapon, _eq.armor)


# ---- 选中 / 使用 / 丢弃 ----
func select_slot(loc: Array) -> void:
	_selected_loc = loc.duplicate()
	refresh_all()


func use_slot(loc: Array) -> void:
	var id := _get_at(loc)
	if id == "" or not DB.has(id):
		return
	var def: Dictionary = DB[id]
	# 消耗品：使用效果 + 消耗一个
	if def.has("use"):
		if String(def["use"]) == "invincible" and _player != null and _player.has_method("gain_invincibility"):
			_player.call("gain_invincibility", float(def.get("dur", 10.0)))
			flash_hint("饮下野生狗奶：10 秒无敌！")
		_set_at(loc, "")
		_selected_loc = []
		refresh_all()
		return
	# 装备：穿戴到对应栏（与当前装备交换）
	var slot := int(def["slot"])
	var key := _kind_to_key(slot)
	if key != "":
		move_item(loc, ["eq", key])


func discard_selected() -> void:
	if _selected_loc.is_empty():
		return
	var id := _get_at(_selected_loc)
	if id == "":
		return
	var loc := _selected_loc.duplicate()
	_set_at(loc, "")
	_selected_loc = []
	refresh_all()
	_sync_player()
	if _player != null and _player.has_method("spawn_drop_box"):
		_player.call("spawn_drop_box", id)
		flash_hint("已丢弃 " + item_name(id) + "（走近按 E 回收）")


func flash_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text
		_hint_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		_hint_t = 2.5


func _process(delta: float) -> void:
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0 and _hint_label != null:
			_hint_label.text = _hint_default
			_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))


# ---- UI ----
func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(838, 340)
	panel.position = (size - panel.size) * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.09, 0.10, 0.13, 0.96)
	for side in ["left", "right", "top", "bottom"]:
		ps.set("border_width_%s" % side, 2)
	ps.border_color = Color(0.45, 0.42, 0.30, 0.9)
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		ps.set("corner_radius_%s" % corner, 10)
	panel.add_theme_stylebox_override("panel", ps)
	dim.add_child(panel)

	var title := Label.new()
	title.text = "背包与装备"
	title.position = Vector2(20, 8)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	panel.add_child(title)

	_hint_default = "Tab 关闭 · 单击选中/双击使用 · 选中后按 E 丢弃 · 拖到装备栏即穿/卸"
	_hint_label = Label.new()
	_hint_label.text = _hint_default
	_hint_label.position = Vector2(20, 312)
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	panel.add_child(_hint_label)

	# 装备栏（左列）：武器 / 副武器 / 防具
	var ey := 52.0
	for d in [["weapon", "武器"], ["subweapon", "副武器"], ["armor", "防具"]] as Array:
		var lbl := Label.new()
		lbl.text = String(d[1])
		lbl.position = Vector2(16, ey + 18)
		lbl.size = Vector2(56, 26)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		panel.add_child(lbl)
		var s := SlotCtl.make(self, ["eq", String(d[0])], SLOT_PX)
		s.position = Vector2(74, ey)
		panel.add_child(s)
		_eq_slots[String(d[0])] = s
		ey += SLOT_PX + GAP + 16.0

	# 背包（右侧 3×9）
	var bx := 262.0
	var by := 52.0
	_bag_slots.clear()
	for i in BAG_SIZE:
		var s2 := SlotCtl.make(self, ["bag", i], SLOT_PX)
		s2.position = Vector2(bx + float(i % BAG_COLS) * (SLOT_PX + GAP), by + float(i / BAG_COLS) * (SLOT_PX + GAP))
		panel.add_child(s2)
		_bag_slots.append(s2)


func refresh_all() -> void:
	for i in _bag_slots.size():
		_paint_slot(_bag_slots[i], bag_get(i))
	for k in _eq_slots:
		_paint_slot(_eq_slots[k], eq_get(k))


func is_selected(loc: Array) -> bool:
	return not _selected_loc.is_empty() and _selected_loc[0] == loc[0] and int(_selected_loc[1]) == int(loc[1])


func _paint_slot(s: Control, id: String) -> void:
	var ic: TextureRect = s.get_meta("icon")
	if id == "":
		ic.visible = false
		s.tooltip_text = ""
	else:
		ic.texture = _items[id].icon
		ic.modulate = DB[id]["tint"]
		ic.visible = true
		s.tooltip_text = "%s\n%s" % [String(DB[id]["name"]), String(DB[id]["desc"])]
	s.call("set_selected", is_selected(s.get_meta("loc")))


# ---- 开关 ----
func _unhandled_input(event: InputEvent) -> void:
	## Tab：关着能开、开着能关（早先写成 not _open 就 return，导致第一次按 Tab 没反应）
	## E：仅面板打开时用于丢弃选中物品；ESC：面板打开时直接关掉（此时 Player 被禁用收键）
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		_toggle()
		get_viewport().set_input_as_handled()
	elif _open and event.keycode == KEY_E:
		discard_selected()
	elif _open and event.keycode == KEY_ESCAPE:
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_open = not _open
	visible = _open
	if _open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _player != null:
			_player.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_selected_loc = []
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _player != null:
			_player.process_mode = Node.PROCESS_MODE_INHERIT
		refresh_all()


# ============================================================
# 槽位控件：Panel + 图标；拖放穿卸 + 单击选中 + 双击使用
# ============================================================
class SlotCtl extends Panel:
	var inv: Node
	var loc: Array
	var _style: StyleBoxFlat
	var _selected := false

	static func make(owner_inv: Node, p_loc: Array, px: float) -> SlotCtl:
		var s := SlotCtl.new()
		s.inv = owner_inv
		s.loc = p_loc
		s.size = Vector2(px, px)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.17, 0.21, 0.95)
		for side in ["left", "right", "top", "bottom"]:
			sb.set("border_width_%s" % side, 2)
		sb.border_color = Color(0.38, 0.40, 0.46)
		for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
			sb.set("corner_radius_%s" % corner, 6)
		s.add_theme_stylebox_override("panel", sb)
		s._style = sb
		var ic := TextureRect.new()
		ic.position = Vector2(7, 7)
		ic.size = Vector2(px - 14, px - 14)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.visible = false
		s.add_child(ic)
		s.set_meta("icon", ic)
		s.set_meta("loc", p_loc)
		s.mouse_entered.connect(s._hover.bind(true))
		s.mouse_exited.connect(s._hover.bind(false))
		return s

	func set_selected(v: bool) -> void:
		_selected = v
		_repaint_border()

	func _repaint_border() -> void:
		if _selected:
			_style.border_color = Color(1.0, 0.85, 0.35)
			_style.bg_color = Color(0.28, 0.25, 0.14, 0.95)
		else:
			_style.border_color = Color(0.38, 0.40, 0.46)
			_style.bg_color = Color(0.16, 0.17, 0.21, 0.95)

	func _hover(_entering: bool) -> void:
		_repaint_border()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				inv.use_slot(loc)
			else:
				inv.select_slot(loc)
			accept_event()

	func _item_id() -> String:
		return inv.bag_get(loc[1]) if loc[0] == "bag" else inv.eq_get(loc[1])

	func _get_drag_data(_p: Vector2) -> Variant:
		var id := _item_id()
		if id == "":
			return null
		var prev := TextureRect.new()
		prev.texture = inv._items[id].icon
		prev.modulate = inv.DB[id]["tint"]
		prev.custom_minimum_size = Vector2(44, 44)
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		set_drag_preview(prev)
		return {"from": loc}

	func _can_drop_data(_p: Vector2, data: Variant) -> bool:
		if not (data is Dictionary) or not data.has("from"):
			return false
		var src: Array = data["from"]
		if src[0] == loc[0] and int(src[1]) == int(loc[1]):
			return false
		var sid: String = inv.bag_get(src[1]) if src[0] == "bag" else inv.eq_get(src[1])
		if loc[0] == "eq" and sid != "" and int(inv.DB[sid]["slot"]) != inv.key_kind(loc[1]):
			return false
		var did := _item_id()
		if src[0] == "eq" and did != "" and int(inv.DB[did]["slot"]) != inv.key_kind(src[1]):
			return false
		return true

	func _drop_data(_p: Vector2, data: Variant) -> void:
		inv.move_item(data["from"], loc)
