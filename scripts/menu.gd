extends Node3D
## 主菜单：中间一瓶旋转的野生狗奶 + 三个按钮（新游戏 / 读取存档 / 输入种子）。
## 全部 UI 用代码搭建（与 HUD、背包一致的风格），存档为 save/ 下的 JSON。
## 选好后写入 SaveManager 的 pending_seed / pending_load，再切到 main.tscn 由游戏侧套用。

const GAME_SCENE := "res://scenes/main.tscn"
const FACE_DIR := "res://assets/props/dogmilk/"

var _bottle: MeshInstance3D
var _root: Control
var _main_box: HBoxContainer
var _seed_box: VBoxContainer
var _save_box: VBoxContainer
var _seed_bg: Panel
var _save_bg: Panel
var _seed_edit: LineEdit
var _status: Label
var _showing := "main"


func _ready() -> void:
	_build_world()
	_build_ui()
	_show("main")


# ---- 3D 背景：天空 + 阳光 + 旋转奶盒 ----
func _build_world() -> void:
	var owe := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.32, 0.52, 0.86)
	psm.sky_horizon_color = Color(0.92, 0.88, 0.80)
	psm.ground_bottom_color = Color(0.35, 0.33, 0.30)
	psm.ground_horizon_color = Color(0.92, 0.88, 0.80)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.4
	owe.environment = env
	add_child(owe)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 5.2)
	cam.fov = 62.0
	add_child(cam)

	# 奶盒：与 BOSS 同款 SurfaceTool 六面贴图小网格（24 顶点，避开大 ArrayMesh 的渲染坑）
	_bottle = MeshInstance3D.new()
	_bottle.mesh = _build_milk_mesh()
	_bottle.position = Vector3(0, 1.35, 0)
	add_child(_bottle)

	# 地面：接住影子，避免奶盒"飘在天上"
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.86, 0.86, 0.88)
	fm.roughness = 0.95
	pm.material = fm
	floor_mi.mesh = pm
	add_child(floor_mi)


func _process(delta: float) -> void:
	if _bottle != null:
		_bottle.rotation.y += delta * 0.85
		_bottle.position.y = 1.35 + 0.08 * sin(Time.get_ticks_msec() / 1000.0 * 1.6)


## 六面贴图奶盒（与 boss.gd 同一套做法）：顶点按"从外侧看逆时针"，法线显式朝外，
## y 以盒中心为基准，方便整体悬浮与绕 Y 旋转。
func _build_milk_mesh() -> ArrayMesh:
	var W := 1.5
	var H := 2.4
	var D := 0.85
	var hx := W / 2.0
	var hy := H / 2.0
	var hz := D / 2.0
	var defs: Array = [
		["front.png", Vector3(0, 0, 1), [Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)]],
		["back.png", Vector3(0, 0, -1), [Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz)]],
		["side.png", Vector3(1, 0, 0), [Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz)]],
		["side.png", Vector3(-1, 0, 0), [Vector3(-hx, -hy, -hz), Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz)]],
		["top.png", Vector3(0, 1, 0), [Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz)]],
		["bottom.png", Vector3(0, -1, 0), [Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz)]],
	]
	var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var mesh := ArrayMesh.new()
	for def in defs:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var verts: Array = def[2]
		var n: Vector3 = def[1]
		st.set_material(_face_mat(String(def[0])))
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit().surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, _face_mat(String(def[0])))
	return mesh


func _face_mat(tex_file: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(FACE_DIR + tex_file)
	m.roughness = 0.65
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ---- UI ----
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_root)

	# 顶部标题
	var title := Label.new()
	title.text = "野生狗奶大乱斗"
	title.position = Vector2(0, 46)
	title.size = Vector2(1280, 62)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.72))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.02, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	_root.add_child(title)

	var sub := Label.new()
	sub.text = "程序化随机地形 · 主副武器 · BOSS 空间挑战"
	sub.position = Vector2(0, 112)
	sub.size = Vector2(1280, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_root.add_child(sub)

	_status = Label.new()
	_status.position = Vector2(0, 654)
	_status.size = Vector2(1280, 24)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_root.add_child(_status)

	var dir_label := Label.new()
	dir_label.text = "存档目录：%s" % SaveManager.save_dir()
	dir_label.position = Vector2(20, 694)
	dir_label.add_theme_font_size_override("font_size", 13)
	dir_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_root.add_child(dir_label)

	# 三个主按钮：屏幕底部横排，中间留给旋转的奶盒
	_main_box = HBoxContainer.new()
	_main_box.position = Vector2(640 - 342, 556)
	_main_box.custom_minimum_size = Vector2(684, 0)
	_main_box.add_theme_constant_override("separation", 18)
	_root.add_child(_main_box)
	_add_button(_main_box, "新游戏", _on_new_game, 216)
	_add_button(_main_box, "读取存档", func(): _show("save"), 216)
	_add_button(_main_box, "输入种子", func(): _show("seed"), 216)

	# 输入种子面板（带深色底板，避免文字糊在 3D 背景上）
	_seed_bg = _panel_behind(Vector2(640 - 190, 236), Vector2(380, 250))
	_seed_box = VBoxContainer.new()
	_seed_box.position = Vector2(640 - 166, 258)
	_seed_box.custom_minimum_size = Vector2(332, 0)
	_seed_box.add_theme_constant_override("separation", 12)
	_root.add_child(_seed_box)
	var tip := Label.new()
	tip.text = "输入地形种子（整数）\n同一种子 = 同一片地形"
	tip.add_theme_font_size_override("font_size", 15)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_seed_box.add_child(tip)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "例如 20260828"
	_seed_edit.custom_minimum_size = Vector2(300, 34)
	_seed_edit.add_theme_font_size_override("font_size", 18)
	_seed_box.add_child(_seed_edit)
	_add_button(_seed_box, "用该种子开始", _on_seed_start)
	_add_button(_seed_box, "返回", func(): _show("main"))

	# 读取存档面板
	_save_bg = _panel_behind(Vector2(640 - 240, 190), Vector2(480, 400))
	_save_box = VBoxContainer.new()
	_save_box.position = Vector2(640 - 216, 210)
	_save_box.custom_minimum_size = Vector2(432, 0)
	_save_box.add_theme_constant_override("separation", 10)
	_root.add_child(_save_box)


func _panel_behind(pos: Vector2, panel_size: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = panel_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.90)
	sb.border_color = Color(0.52, 0.46, 0.28, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.visible = false
	_root.add_child(p)
	return p


func _add_button(parent: Control, text: String, cb: Callable, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 44)
	b.add_theme_font_size_override("font_size", 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.15, 0.88)
	sb.border_color = Color(0.55, 0.50, 0.32, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate()
	hover.bg_color = Color(0.24, 0.21, 0.10, 0.95)
	hover.border_color = Color(1.0, 0.85, 0.35)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	b.add_theme_color_override("font_hover_color", Color(1, 0.9, 0.45))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _show(which: String) -> void:
	_showing = which
	_main_box.visible = which == "main"
	_seed_box.visible = which == "seed"
	_save_box.visible = which == "save"
	if _seed_bg != null:
		_seed_bg.visible = which == "seed"
	if _save_bg != null:
		_save_bg.visible = which == "save"
	if which == "seed":
		_seed_edit.grab_focus()
	if which == "save":
		_rebuild_save_list()


func _rebuild_save_list() -> void:
	for c in _save_box.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = "选择要读取的存档"
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_save_box.add_child(head)

	var saves: Array = SaveManager.list_saves()
	if saves.is_empty():
		var empty := Label.new()
		empty.text = "还没有存档。\n先「新游戏」，进游戏后按 F5 保存。"
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		_save_box.add_child(empty)
	else:
		for entry in saves:
			var b := _add_button(_save_box, SaveManager.describe(entry), _on_load.bind(String(entry.path)))
			b.add_theme_font_size_override("font_size", 15)
			b.custom_minimum_size = Vector2(0, 36)
	_save_box.add_child(_make_spacer())
	_add_button(_save_box, "返回", func(): _show("main"))


func _make_spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 6)
	return c


# ---- 行为 ----
func _on_new_game() -> void:
	SaveManager.stage_new_game(-1)
	_start("新游戏：地形随机生成")


func _on_seed_start() -> void:
	var txt := _seed_edit.text.strip_edges()
	if txt.is_empty() or not txt.is_valid_int():
		_status.text = "请输入一个整数种子"
		return
	SaveManager.stage_new_game(int(txt))
	_start("新游戏：种子 %s" % txt)


func _on_load(path: String) -> void:
	SaveManager.stage_load(path)
	if SaveManager.pending_load.is_empty():
		_status.text = "存档读取失败：文件损坏或不是 JSON"
		return
	_start("已读取存档：%s" % path.get_file())


func _start(msg: String) -> void:
	print("[menu] %s" % msg)
	get_tree().change_scene_to_file(GAME_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _showing != "main":
			_show("main")
		elif event.keycode == KEY_ENTER and _showing == "seed":
			_on_seed_start()
