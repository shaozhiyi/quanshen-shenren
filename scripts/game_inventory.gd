extends Control
## 背包 & 装备栏（Tab 开关；打开期间整局暂停，关闭即恢复）。
## 数据层复用 Godot 素材库插件 addons/grid_inventory（MIT, GodotForge）的
## Inventory / InvItem 类；物品图标取自 game-icons.net（CC-BY 4.0，见 assets/items/CREDITS.txt）。
## 装备栏：武器 / 副武器 / 防具；背包 3 行 × 9 列。默认装备剑+弓箭+防具（防具自动穿戴）。
## 武器一共三把（剑 / 弓箭 / 法杖），但装备栏只有两格 → 只能带其中两把，
## 哪两把由玩家自己拖：法杖可以放「武器」栏也可以放「副武器」栏，换第三把就得先卸一把。
## 法杖初始放在背包第一格。
## 交互：拖拽穿卸；单击选中；双击武器/防具＝只强化这一件（吃 1 块强化石）；
##       双击消耗品＝使用一次；选中后按 E 丢弃→地上生成箱子。
const BAG_SIZE := 27
const BAG_COLS := 9
const SLOT_PX := 58.0
const GAP := 6.0
# 装备栏只有这三格（早先给法杖单开过第四格，已并回武器栏：三把武器抢两格）
const EQ_KEYS := ["weapon", "subweapon", "armor"]
# 堆叠：消耗品可堆到同格，格子上显示 ×2/×3…；上限 20
const STACK_MAX := 20
const STACKABLE := ["dogmilk", "stone"]
# id -> 定义：名称/可去的装备栏(空=不可装备)/图标/着色/属性说明/[use]
# 可强化的对象 = 有装备去处的东西，等级由玩家身上的 enhance_levels 保管
const DB := {
	"sword":  {"name": "剑", "eq": ["weapon", "subweapon"], "icon": "res://assets/items/sword.svg", "tint": Color(0.88, 0.92, 0.98),
		"desc": "武器 · 基础攻击 50，按 X 挥砍\n可放「武器」或「副武器」栏\n双击：花 1 块强化石 → 只有剑 +1 级\n每级攻击力 ×1.1 后向下取整（最高 +10）\n50 → 55 → 60 → 66 → 73 → 80 …"},
	"bow":    {"name": "弓箭", "eq": ["weapon", "subweapon"], "icon": "res://assets/items/bow.svg", "tint": Color(0.95, 0.80, 0.62),
		"desc": "武器 · 蓄力 2 秒满，攻击 12~70\n按住左键蓄力，松手发射，每箭冷却 0.5 秒\n可放「武器」或「副武器」栏\n双击：花 1 块强化石 → 只有弓箭 +1 级\n每级攻击力 ×1.1 后向下取整（最高 +10）"},
	"armor":  {"name": "防具", "eq": ["armor"], "icon": "res://assets/items/armor.svg", "tint": Color(1.00, 0.85, 0.40),
		"desc": "护甲 · 受到的伤害 ×0.7 后向下取整\n双击：花 1 块强化石 → 只有防具 +1 级\n每级再减 3% 受伤（最低 ×0.4）\n（不足 1 点的零头会累计到之后扣）"},
	"staff":  {"name": "法杖", "eq": ["weapon", "subweapon"], "icon": "res://assets/items/staff.svg", "tint": Color(0.78, 0.70, 1.00),
		"desc": "武器 · 点 X / 左键甩杖射出一颗魔法球，冷却 3 秒\n按住不放蓄力最多 4 秒，松手射出更大的球\n球色随机：红＝伤害 80（蓄满 140）\n蓝＝伤害 50（蓄满 90）+ 定身 1 秒（蓄满 1.5 秒）\n定身只冻住 BOSS，不打断它正在做的动作\n可放「武器」或「副武器」栏：三把武器只能带两把\n装它之前先把另一格里的武器拖回背包\n双击：花 1 块强化石 → 只有法杖 +1 级"},
	"dogmilk": {"name": "野生狗奶", "eq": [], "icon": "res://assets/items/dogmilk.png", "tint": Color(1, 1, 1),
		"desc": "「生命惧怕时间，时间惧怕野生狗奶。」\n\n消耗品 · 双击饮用\n获得 10 秒无敌（免疫伤害），\n血条变金、数字显示「永久」\n10 秒后解除并恢复满血",
		"use": "invincible", "dur": 10.0},
	"stone":  {"name": "装备强化石", "eq": [], "icon": "res://assets/items/stone.svg", "tint": Color(0.60, 0.86, 1.00),
		"desc": "强化材料 · 双击不会消耗\n拿去双击「武器 / 防具」→ 只强化那一件，本石 -1\n\n击杀野生狗奶必掉 1 块，\n之后以 4%、3.95%、3.90%… 逐次递减追加"},
}
var _bag: Inventory                 # addons/grid_inventory 的数据模型（27 格）
var _items := {}                    # id -> InvItem
var _bag_n: Array = []              # 每格物品数量（与 _bag.slots 同长）
var _eq := {"weapon": "sword", "subweapon": "bow", "armor": "armor"}
var _eq_slots := {}                 # key -> SlotCtl
var _bag_slots: Array = []
var _player: Node
var _open := false
var freeze_whole_tree := true       # 单机开包=整局暂停；联机关掉（只禁本机玩家输入）
var _selected_loc: Array = []       # 当前选中的槽位 ["bag",i]/["eq",k]
var _hint_label: Label
func _ready() -> void:
	# 背包打开时会暂停整棵树，本面板必须在暂停态下也照常收输入；
	# 注意 WHEN_PAUSED 是"只在暂停时处理"（那样平时按 Tab 就没反应了），所以要用 ALWAYS
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 直接挂在 CanvasLayer 下的 Control 不会自动继承视口尺寸（联机 HUD 的背包就是这样：
	# size 恒为 0 → 面板居中算出负坐标跑到屏幕外、全屏暗衬也铺不开）。
	# 显式绑定视口大小，并跟随窗口尺寸变化。
	_sync_viewport_size()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_sync_viewport_size):
		vp.size_changed.connect(_sync_viewport_size)
	visible = false
	_player = get_node_or_null("../../Player")
	if _player == null:
		var locals := get_tree().get_nodes_in_group("local_player")
		if not locals.is_empty():
			_player = locals[0]     # PVP 竞技场：本机玩家的节点不叫 Player
	_build_items()
	_build_bag()
	_build_ui()
	if not SaveManager.pending_load.is_empty():
		load_state(SaveManager.pending_load)
	else:
		refresh_all()
		_sync_player()
## 存档：导出装备栏、背包内容与每格堆叠数量
func save_state() -> Dictionary:
	var bag: Array = []
	var counts: Array = []
	for i in BAG_SIZE:
		bag.append(bag_get(i))
		counts.append(bag_count(i))
	return {"equipment": _eq.duplicate(), "bag": bag, "bag_counts": counts}
## 读档：还原装备栏、背包（含数量），并把"手上拿的哪把武器"同步回玩家
func load_state(save: Dictionary) -> void:
	var eq: Dictionary = save.get("equipment", {})
	for k in EQ_KEYS:
		_eq[k] = String(eq[k]) if eq.has(k) else ""
	var bag: Array = save.get("bag", [])
	var counts: Array = save.get("bag_counts", [])
	for i in mini(bag.size(), BAG_SIZE):
		var n := int(counts[i]) if i < counts.size() else 1
		bag_set(i, String(bag[i]), maxi(n, 1))
	# 老存档那根放在「法杖」第四格里的杖，这一版没那格了 → 由 _ensure_staff 补回背包
	_ensure_staff()
	refresh_all()
	_sync_player()
	var w := int(save.get("player", {}).get("weapon", 0))
	if _player != null and _player.has_method("set_current_weapon"):
		_player.call("set_current_weapon", w)
func _ensure_staff() -> void:
	## 老存档没有法杖（既不在装备栏也不在背包）→ 补发一根。
	## 优先塞进空着的武器栏（本来就缺武器），否则放第一个空格；都没位置就算了，
	## 绝不挤掉玩家已有的东西。
	if count_of("staff") > 0:
		return
	var key := _first_free_eq_for("staff")
	if key != "":
		_eq[key] = "staff"
		return
	var i := _first_empty_bag()
	if i >= 0:
		bag_set(i, "staff", 1)
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
	_bag_n.clear()
	for i in BAG_SIZE:
		_bag_n.append(0)
	# 防具自动穿戴（_eq.armor 默认已为 armor）；法杖初始放在背包第一格，
	# 想用它就得自己拖进「武器」或「副武器」栏（另换一把回背包）
	bag_set(0, "staff", 1)
## 联机 PVP 的初始配置：剑+弓、法杖在背包、自带一瓶野生狗奶（效果不变）、不穿甲
func setup_pvp() -> void:
	freeze_whole_tree = false
	_eq.armor = ""
	bag_set(0, "staff", 1)
	bag_set(1, "dogmilk", 1)
	refresh_all()
	_sync_player()
func item_name(id: String) -> String:
	return String(DB[id]["name"]) if DB.has(id) else id
static func is_stackable(id: String) -> bool:
	return STACKABLE.has(id)
func stack_max_of(id: String) -> int:
	return STACK_MAX if STACKABLE.has(id) else 1
## 对外：加入物品（可指定数量）。可装备且有空栏位→自动穿戴；
## 可堆叠物品先补满已有堆，再占用新格子。
## 返回是否全部放下：部分放下时已放的保留，返回值 false 供调用方提示"背包已满"。
func add_item(id: String, count: int = 1) -> bool:
	if not DB.has(id) or count <= 0:
		return false
	var left := count
	var placed := 0
	# 仅首件走"自动穿戴"逻辑，其余进背包。武器三把但只有两格，两格都满就老实进背包。
	if is_equippable(id):
		var key := _first_free_eq_for(id)
		if key != "":
			_eq[key] = id
			left -= 1
			placed += 1
	var cap := stack_max_of(id)
	if cap > 1:
		# 先补已有的堆
		for i in BAG_SIZE:
			if left <= 0:
				break
			if bag_get(i) == id and bag_count(i) < cap:
				var room := cap - bag_count(i)
				var take := mini(room, left)
				bag_set(i, id, bag_count(i) + take)
				left -= take
				placed += take
	while left > 0:
		var idx := _first_empty_bag()
		if idx < 0:
			break
		var take2 := mini(cap, left)
		bag_set(idx, id, take2)
		left -= take2
		placed += take2
	refresh_all()
	if placed > 0:
		_sync_player()
	return placed >= count
## 统计某 id 在背包+装备栏的总数量（按堆叠数累加）
func count_of(id: String) -> int:
	var n := 0
	for i in BAG_SIZE:
		if bag_get(i) == id:
			n += bag_count(i)
	for k in _eq:
		if _eq[k] == id:
			n += 1
	return n
func _first_empty_bag() -> int:
	for i in BAG_SIZE:
		if bag_get(i) == "":
			return i
	return -1
func eq_slots_for(id: String) -> Array:
	## 这件东西能去的装备栏（不可装备 → 空数组）
	if not DB.has(id):
		return []
	return DB[id].get("eq", []) as Array
func is_equippable(id: String) -> bool:
	return not eq_slots_for(id).is_empty()
func can_equip(id: String, key: String) -> bool:
	## 拖放判定：这件物品允不允许落在某一格里
	return eq_slots_for(id).has(key)
func _first_free_eq_for(id: String) -> String:
	## 按装备栏从左到右找第一个"能放且空着"的格子；没有就返回 ""
	for key in eq_slots_for(id):
		var k := String(key)
		if _eq.has(k) and String(_eq[k]) == "":
			return k
	return ""
func bag_get(i: int) -> String:
	var s = _bag.slots[i]
	return String(s.item.id) if s != null else ""
func bag_count(i: int) -> int:
	return int(_bag_n[i]) if i < _bag_n.size() else 0
func bag_set(i: int, id: String, n: int = 1) -> void:
	_bag.slots[i] = ({"item": _items[id]} if id != "" else null)
	while _bag_n.size() <= i:
		_bag_n.append(0)
	_bag_n[i] = (mini(n, stack_max_of(id)) if id != "" else 0)
func eq_get(k: String) -> String:
	## 老存档/老调用可能问起已经不存在的「staff」栏，这里返回空而不是崩
	return String(_eq[k]) if _eq.has(k) else ""
func eq_set(k: String, id: String) -> void:
	_eq[k] = id
## 统一搬移：src/dst = ["bag", idx] 或 ["eq", key]；栏位不收这类东西返回 false
func move_item(src: Array, dst: Array) -> bool:
	# 注意：装备栏的下标是字符串（"weapon"/"subweapon"），背包的是数字。
	# 这里绝不能 int() 归一化——int("weapon") 和 int("subweapon") 都等于 0，
	# 会把"武器栏拖到副武器栏"误判成"原地不动"而拒绝（三把武器共用两格之后必踩）。
	if src[0] == dst[0] and str(src[1]) == str(dst[1]):
		return false
	var sid := _get_at(src)
	var did := _get_at(dst)
	if dst[0] == "eq" and sid != "" and not can_equip(sid, str(dst[1])):
		return false
	if src[0] == "eq" and did != "" and not can_equip(did, str(src[1])):
		return false
	# 同种可堆叠物品拖到同一格 → 合并（装不下的留在原格）
	if src[0] == "bag" and dst[0] == "bag" and sid != "" and sid == did and is_stackable(sid):
		var cap := stack_max_of(sid)
		var have := _count_at(dst)
		var move_n := _count_at(src)
		var take: int = mini(cap - have, move_n)
		if take <= 0:
			return false
		bag_set(int(dst[1]), sid, have + take)
		bag_set(int(src[1]), sid if take < move_n else "", move_n - take)
		refresh_all()
		_sync_player()
		return true
	var sn := _count_at(src)
	var dn := _count_at(dst)
	_set_at(dst, sid, sn)
	_set_at(src, did, dn)
	refresh_all()
	_sync_player()
	return true
func _get_at(loc: Array) -> String:
	return bag_get(loc[1]) if loc[0] == "bag" else eq_get(loc[1])
func _count_at(loc: Array) -> int:
	return bag_count(int(loc[1])) if loc[0] == "bag" else 1
func _set_at(loc: Array, id: String, n: int = 1) -> void:
	if loc[0] == "bag":
		bag_set(int(loc[1]), id, n)
	else:
		eq_set(str(loc[1]), id)
func _sync_player() -> void:
	## 只报三格的内容（武器/副武器/防具）；哪几把武器在身上由玩家按 id 认，不看格子名
	if _player != null and _player.has_method("set_equipment"):
		_player.call("set_equipment", _eq.weapon, _eq.subweapon, _eq.armor)
# ---- 选中 / 使用 / 丢弃 ----
func select_slot(loc: Array) -> void:
	_selected_loc = loc.duplicate()
	refresh_all()
## 该 id 当前强化等级（等级由玩家保管，取不到按 0）
func _lv(id: String) -> int:
	if _player != null and _player.has_method("enhance_level_of"):
		return int(_player.call("enhance_level_of", id))
	return 0
## 强化封顶等级（问玩家要，取不到按 10）
func _enh_max() -> int:
	if _player != null and _player.has_method("enhance_max"):
		return int(_player.call("enhance_max"))
	return 10
func is_enhanceable(id: String) -> bool:
	## 能装备的就是可强化对象（剑 / 弓箭 / 法杖 / 防具），各自独立计级
	return is_equippable(id)
func stones_held() -> int:
	return count_of("stone")
## 从背包里扣掉 1 块强化石（先扣尾堆，保持前排格子数字大）
func _take_one_stone() -> bool:
	for i in range(BAG_SIZE - 1, -1, -1):
		if bag_get(i) == "stone":
			var n := bag_count(i) - 1
			bag_set(i, "stone" if n > 0 else "", maxi(n, 0))
			return true
	return false
## 双击某件武器/装备：只强化这一件，并消耗 1 块强化石（无提示，成功与否看格子上的 +N）
func enhance_at(loc: Array) -> bool:
	var id := _get_at(loc)
	if not is_enhanceable(id):
		return false
	if _player == null or not _player.has_method("enhance_item"):
		return false
	if stones_held() <= 0:
		return false
	# 满级等情况玩家会返回 false，此时不吃石头
	if not bool(_player.call("enhance_item", id)):
		refresh_all()
		return false
	_take_one_stone()
	refresh_all()
	_sync_player()
	return true
func use_slot(loc: Array) -> void:
	var id := _get_at(loc)
	if id == "" or not DB.has(id):
		return
	# 装备类：双击＝强化这一件（消耗强化石），穿卸请用拖拽
	if is_enhanceable(id):
		enhance_at(loc)
		return
	var def: Dictionary = DB[id]
	if id == "stone":
		return        # 石头是材料，双击不消耗
	# 消耗品：生效一次并只扣 1 个（堆叠见底才空格）
	if def.has("use"):
		var kind := String(def["use"])
		if kind == "invincible" and _player != null and _player.has_method("gain_invincibility"):
			_player.call("gain_invincibility", float(def.get("dur", 10.0)))
		var n := _count_at(loc) - 1
		_set_at(loc, id if n > 0 else "", maxi(n, 0))
		if n <= 0:
			_selected_loc = []
		refresh_all()
		_sync_player()
func discard_selected() -> void:
	if _selected_loc.is_empty():
		return
	var id := _get_at(_selected_loc)
	if id == "":
		return
	var loc := _selected_loc.duplicate()
	var n := _count_at(loc)
	_set_at(loc, "", 0)
	_selected_loc = []
	refresh_all()
	_sync_player()
	if _player != null and _player.has_method("spawn_drop_box"):
		_player.call("spawn_drop_box", id, n)
# ---- UI ----
func _sync_viewport_size() -> void:
	## 把自身矩形钉到视口大小：挂在 CanvasLayer 下的 Control 不会自动拿到视口尺寸
	position = Vector2.ZERO
	size = get_viewport_rect().size
func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := Panel.new()
	panel.size = Vector2(838, 340)
	# 居中必须走锚点，不能用 (size - panel.size) * 0.5：
	# 联机里背包直接挂在 CanvasLayer 下，_ready 时自身 size 还是 0，
	# 那样算出负坐标，整块面板会跑到屏幕左上角外面（格子和文字全被切掉）
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -419.0
	panel.offset_right = 419.0
	panel.offset_top = -170.0
	panel.offset_bottom = 170.0
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
	_hint_label = Label.new()
	_hint_label.text = "Tab 关闭 · 拖到装备栏穿/卸（三把武器只能带两把）· 双击武器或装备＝强化（耗 1 块强化石）· 双击狗奶＝喝 · 选中按 E 丢弃"
	_hint_label.position = Vector2(20, 312)
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	panel.add_child(_hint_label)
	# 装备栏（左列）：武器 / 副武器 / 防具。剑、弓、法杖三把都只能落在前两格，选两把带身上
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
		_paint_slot(_bag_slots[i], bag_get(i), bag_count(i))
	for k in _eq_slots:
		_paint_slot(_eq_slots[k], eq_get(k), 1)
func is_selected(loc: Array) -> bool:
	## 同 move_item：槽位标识可能是字符串（装备栏）也可能是数字（背包），按字符串比才准
	return not _selected_loc.is_empty() and _selected_loc[0] == loc[0] \
		and str(_selected_loc[1]) == str(loc[1])
func _paint_slot(s: Control, id: String, n: int = 1) -> void:
	var ic: TextureRect = s.get_meta("icon")
	var cnt: Label = s.get_meta("count")
	var enh: Label = s.get_meta("enh")
	if id == "":
		ic.visible = false
		s.tooltip_text = ""
		cnt.visible = false
		enh.visible = false
	else:
		ic.texture = _items[id].icon
		ic.modulate = DB[id]["tint"]
		ic.visible = true
		var cap := stack_max_of(id)
		if n > 1:
			cnt.text = "×%d" % n
			cnt.visible = true
		else:
			cnt.visible = false
		# 左上角 +N：每件装备自己的强化等级（各自独立，最高 +10）
		var lv := _lv(id)
		if is_enhanceable(id) and lv > 0:
			enh.text = "+%d" % lv
			enh.visible = true
		else:
			enh.visible = false
		var tip := "%s%s\n%s" % [String(DB[id]["name"]), (" ×%d/%d" % [n, cap]) if cap > 1 else "", String(DB[id]["desc"])]
		if is_enhanceable(id):
			tip += "\n\n当前 +%d / %d ｜ 持有强化石 ×%d" % [lv, _enh_max(), stones_held()]
		s.tooltip_text = tip
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
		if freeze_whole_tree:
			get_tree().paused = true      # 单机：开包即暂停（BOSS、箭、特效全部冻住）
		# 联机：整棵树不能停（别人的画面会卡住），本机玩家已被禁输入 = 你站着挨打
	else:
		_selected_loc = []
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if freeze_whole_tree:
			get_tree().paused = false     # 先解除暂停，再恢复玩家（顺序反了会卡在暂停里）
		if _player != null:
			_player.process_mode = Node.PROCESS_MODE_INHERIT
		refresh_all()
func _exit_tree() -> void:
	## 切场景/重开时兜底：绝不把 paused=true 留给下一个场景
	if get_tree() != null:
		get_tree().paused = false
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
		var cn := Label.new()
		cn.position = Vector2(px - 34, px - 23)
		cn.size = Vector2(30, 19)
		cn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cn.add_theme_font_size_override("font_size", 15)
		cn.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
		cn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		cn.add_theme_constant_override("outline_size", 5)
		cn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cn.visible = false
		s.add_child(cn)
		s.set_meta("count", cn)
		var ic := TextureRect.new()
		ic.position = Vector2(7, 7)
		ic.size = Vector2(px - 14, px - 14)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.visible = false
		s.add_child(ic)
		s.set_meta("icon", ic)
		var en := Label.new()
		en.position = Vector2(3, 1)
		en.size = Vector2(34, 18)
		en.add_theme_font_size_override("font_size", 14)
		en.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))
		en.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		en.add_theme_constant_override("outline_size", 5)
		en.mouse_filter = Control.MOUSE_FILTER_IGNORE
		en.visible = false
		s.add_child(en)
		s.set_meta("enh", en)
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
		if src[0] == loc[0] and str(src[1]) == str(loc[1]):
			return false     # 拖回自己那一格不算（同样别用 int() 比，见 move_item 注释）
		var sid: String = inv.bag_get(src[1]) if src[0] == "bag" else inv.eq_get(src[1])
		if loc[0] == "eq" and sid != "" and not inv.can_equip(sid, str(loc[1])):
			return false
		var did := _item_id()
		if src[0] == "eq" and did != "" and not inv.can_equip(did, str(src[1])):
			return false
		return true
	func _drop_data(_p: Vector2, data: Variant) -> void:
		inv.move_item(data["from"], loc)
