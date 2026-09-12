extends CanvasLayer
## 对话框引擎（全局 autoload：Dialogue）。数据驱动的通用剧情演出层。
## 台词内容全部在 scripts/dialogue_data.gd 里用变量维护，这里只管播放。
##
## 对外接口：
##   Dialogue.play(id_or_lines, opts)   # opts: {vars, speed, pause, on_done}
##   Dialogue.is_showing() -> bool
##   Dialogue.advance()                 # 打字中=瞬间显示整行；否则下一句
##   Dialogue.stop()                    # 立即结束
## 信号：started / line_shown(index) / finished
##
## 底部功能条（可点，也可用键盘）：
##   » 跳过   A 自动   S 存档   L 读档   Ctrl+S 快存   Ctrl+L 快读   ↺ 历史
## 存档/读档保存的是「当前这段剧情的播放进度」(台词+序号+变量)，写到 user:// 下，
## 与游戏本体存档相互独立，方便正经模式剧情断点续读。

signal started
signal line_shown(index: int)
signal finished

const DATA := preload("res://scripts/dialogue_data.gd")
const AUTO_DELAY := 1.4          # 自动模式：整行显示完后停留秒数再翻页
const SAVE_PREFIX := "user://dialogue_"   # 对话进度存档前缀
const SLOT_MAIN := "slot"        # 存档/读档用的槽
const SLOT_QUICK := "quick"      # 快存/快读用的槽

var _root: Control
var _panel: Panel
var _who: Label
var _text: Label
var _hint: Label
var _bar: HBoxContainer
var _btn_auto: Button
var _btn_history: Button
var _log_panel: Panel
var _log_box: VBoxContainer

var _lines: Array = []
var _idx := -1
var _vars := {}
var _full := ""          # 当前行替换占位符后的完整文本
var _typed := 0.0        # 已显示的字符数（打字机进度）
var _speed := 34.0
var _active := false
var _pause := true
var _on_done := Callable()
var _auto := false
var _auto_wait := 0.0
var _history: Array = []         # 本次运行累计的 {who,text}，供历史回看
var _history_open := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时也要能打字/翻页
	_ensure_ui()
	if not _active:
		visible = false

func _ensure_ui() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = Panel.new()
	_panel.anchor_left = 0.05
	_panel.anchor_right = 0.95
	_panel.anchor_top = 0.66
	_panel.anchor_bottom = 0.97
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.93)
	sb.border_color = Color(0.62, 0.55, 0.32, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 16
	sb.content_margin_bottom = 40   # 底部留给功能条
	_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_panel)

	_who = Label.new()
	_who.anchor_right = 1.0
	_who.offset_left = 26
	_who.offset_top = 12
	_who.offset_bottom = 40
	_who.add_theme_font_size_override("font_size", 20)
	_who.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	_who.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.02, 0.9))
	_who.add_theme_constant_override("outline_size", 6)
	_panel.add_child(_who)

	_text = Label.new()
	_text.anchor_right = 1.0
	_text.anchor_bottom = 1.0
	_text.offset_left = 26
	_text.offset_right = -26
	_text.offset_top = 46
	_text.offset_bottom = -42
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 21)
	_text.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_text.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.85))
	_text.add_theme_constant_override("outline_size", 4)
	_panel.add_child(_text)

	_hint = Label.new()
	_hint.text = "▼"
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -40
	_hint.offset_top = -44
	_hint.offset_right = -18
	_hint.offset_bottom = -42
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	_hint.visible = false
	_panel.add_child(_hint)

	_build_bar()
	_build_history()

## ---- 底部功能条 ----
func _build_bar() -> void:
	_bar = HBoxContainer.new()
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_left = 20
	_bar.offset_right = -20
	_bar.offset_top = -34
	_bar.offset_bottom = -6
	_bar.add_theme_constant_override("separation", 6)
	_panel.add_child(_bar)
	_bar.add_child(_bar_item("»", "跳过", _skip))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(spacer)
	_btn_auto = _bar_item("A", "自动", _toggle_auto)
	_bar.add_child(_btn_auto)
	_bar.add_child(_bar_item("S", "存档", func(): _save(SLOT_MAIN)))
	_bar.add_child(_bar_item("L", "读档", func(): _load(SLOT_MAIN)))
	_bar.add_child(_bar_item("QS", "快存", func(): _save(SLOT_QUICK)))
	_bar.add_child(_bar_item("QL", "快读", func(): _load(SLOT_QUICK)))
	_btn_history = _bar_item("↺", "历史", _toggle_history)
	_bar.add_child(_btn_history)

func _bar_item(key_hint: String, label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(1, 1, 1, 0.10)
	hov.set_corner_radius_all(6)
	hov.content_margin_left = 10
	hov.content_margin_right = 10
	b.add_theme_stylebox_override("hover", hov)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kl := Label.new()
	kl.text = key_hint
	kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kl.add_theme_font_size_override("font_size", 13)
	kl.add_theme_color_override("font_color", Color(1, 1, 1, 0.42))
	var tl := Label.new()
	tl.text = label
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_theme_font_size_override("font_size", 16)
	tl.add_theme_color_override("font_color", Color(0.92, 0.93, 0.98))
	hb.add_child(kl)
	hb.add_child(tl)
	b.add_child(hb)
	b.custom_minimum_size = Vector2(hb.get_combined_minimum_size().x + 26, 28)
	b.pressed.connect(cb)
	return b

## ---- 历史回看面板 ----
func _build_history() -> void:
	_log_panel = Panel.new()
	_log_panel.anchor_left = 0.12
	_log_panel.anchor_right = 0.88
	_log_panel.anchor_top = 0.08
	_log_panel.anchor_bottom = 0.92
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.97)
	sb.border_color = Color(0.62, 0.55, 0.32, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_log_panel.add_theme_stylebox_override("panel", sb)
	_log_panel.visible = false
	_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_log_panel)
	_log_panel.gui_input.connect(_on_log_input)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 22
	scroll.offset_right = -22
	scroll.offset_top = 16
	scroll.offset_bottom = -16
	_log_panel.add_child(scroll)
	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_log_box)

func _on_log_input(event: InputEvent) -> void:
	if _history_open and event is InputEventMouseButton and event.pressed:
		_toggle_history()

func _rebuild_history() -> void:
	for c in _log_box.get_children():
		c.queue_free()
	for e in _history:
		var line := RichTextLabel.new()
		line.bbcode_enabled = true
		line.fit_content = true
		line.scroll_active = false
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("normal_font_size", 18)
		var who := String(e.get("who", ""))
		if who.is_empty():
			line.text = "[color=#8a90a6]%s[/color]" % String(e.get("text", ""))
		else:
			line.text = "[color=#ffd86b]%s[/color]  [color=#eef1fb]%s[/color]" % [who, String(e.get("text", ""))]
		_log_box.add_child(line)

## ---- 对外接口 ----
func play(id_or_lines, opts := {}) -> void:
	_ensure_ui()
	var lines: Array = []
	if id_or_lines is Array:
		lines = id_or_lines
	else:
		lines = DATA.get_lines(String(id_or_lines))
	if lines.is_empty():
		push_warning("Dialogue.play：没有可播放的台词（%s）" % str(id_or_lines))
		return
	_lines = lines
	_vars = DATA.VARS.duplicate(true)
	if opts.get("vars") is Dictionary:
		_vars.merge(opts.get("vars"), true)   # overwrite=true：传入变量要能盖掉默认
	_speed = float(opts.get("speed", DATA.DEFAULT_SPEED))
	_pause = bool(opts.get("pause", true))
	_on_done = opts.get("on_done", Callable())
	_idx = -1
	_auto = false
	_auto_wait = 0.0
	_history = []
	_active = true
	visible = true
	_sync_bar()
	if _pause:
		get_tree().paused = true
	started.emit()
	_next()

func is_showing() -> bool:
	return _active

func advance() -> void:
	if not _active:
		return
	if _history_open:
		_toggle_history()
		return
	if _typed < float(_full.length()):
		_typed = float(_full.length())   # 打字未完：瞬间显示整行
		_render()
	else:
		_next()                          # 整行已出：下一句

func stop() -> void:
	if _active:
		_close()

## ---- 内部 ----
func _next() -> void:
	_idx += 1
	_auto_wait = 0.0
	if _idx >= _lines.size():
		_close()
		return
	var line: Dictionary = _lines[_idx]
	_who.text = _resolve(String(line.get("who", "")))
	_who.visible = not String(_who.text).is_empty()
	_full = _resolve(String(line.get("text", "")))
	_typed = 0.0
	_hint.visible = false
	_history.append({"who": _who.text, "text": _full})
	_render()
	line_shown.emit(_idx)

func _close() -> void:
	_active = false
	visible = false
	_hint.visible = false
	_history_open = false
	_log_panel.visible = false
	_auto = false
	if _pause:
		get_tree().paused = false
	finished.emit()
	if _on_done.is_valid():
		_on_done.call()

func _resolve(s: String) -> String:
	for k in _vars:
		s = s.replace("{" + String(k) + "}", String(_vars[k]))
	return s

func _render() -> void:
	_text.text = _full.substr(0, int(_typed))
	_hint.visible = _typed >= float(_full.length())

func _process(delta: float) -> void:
	if not _active or _history_open:
		return
	if _typed < float(_full.length()):
		_typed = minf(_typed + _speed * delta, float(_full.length()))
		_render()
	elif _auto:
		_auto_wait += delta
		if _auto_wait >= AUTO_DELAY:
			_auto_wait = 0.0
			_next()

## ---- 功能条行为 ----
func _skip() -> void:
	# 跳到这段剧情结尾
	if not _active:
		return
	_idx = _lines.size()
	_close()

func _toggle_auto() -> void:
	_auto = not _auto
	_auto_wait = 0.0
	_sync_bar()

func _toggle_history() -> void:
	_history_open = not _history_open
	if _history_open:
		_rebuild_history()
	_log_panel.visible = _history_open
	_sync_bar()

func _sync_bar() -> void:
	if _btn_auto != null:
		var col := Color(1.0, 0.85, 0.42) if _auto else Color(0.92, 0.93, 0.98)
		for c in _btn_auto.get_children():
			for l in (c as Control).get_children():
				if l is Label and String((l as Label).text) == "自动":
					(l as Label).add_theme_color_override("font_color", col)
	if _btn_history != null:
		var hc := Color(1.0, 0.85, 0.42) if _history_open else Color(0.92, 0.93, 0.98)
		for c in _btn_history.get_children():
			for l in (c as Control).get_children():
				if l is Label and String((l as Label).text) == "历史":
					(l as Label).add_theme_color_override("font_color", hc)

## ---- 对话进度存档 / 读档 ----
func _save_path(slot: String) -> String:
	return SAVE_PREFIX + slot + ".json"

func _save(slot: String) -> void:
	if not _active:
		return
	var data := {
		"lines": _lines, "index": _idx, "vars": _vars,
		"speed": _speed, "pause": _pause, "history": _history,
	}
	var f := FileAccess.open(_save_path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("Dialogue：存档失败 %s" % _save_path(slot))
		return
	f.store_string(JSON.stringify(data))
	f.close()

func _load(slot: String) -> void:
	var f := FileAccess.open(_save_path(slot), FileAccess.READ)
	if f == null:
		push_warning("Dialogue：没有该存档 %s" % _save_path(slot))
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("Dialogue：存档损坏")
		return
	var d: Dictionary = parsed
	_ensure_ui()
	_lines = d.get("lines", [])
	_vars = d.get("vars", {})
	_speed = float(d.get("speed", DATA.DEFAULT_SPEED))
	_pause = bool(d.get("pause", true))
	_history = d.get("history", [])
	_idx = int(d.get("index", 0)) - 1
	_auto = false
	_auto_wait = 0.0
	_on_done = Callable()
	_history_open = false
	_log_panel.visible = false
	_active = true
	visible = true
	_sync_bar()
	if _pause:
		get_tree().paused = true
	_next()   # 从记录的这一句继续

## ---- 输入 ----
func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_S:
					_save(SLOT_QUICK)
					get_viewport().set_input_as_handled()
					return
				KEY_L:
					_load(SLOT_QUICK)
					get_viewport().set_input_as_handled()
					return
		match event.physical_keycode:
			KEY_A:
				_toggle_auto()
				get_viewport().set_input_as_handled()
				return
			KEY_S:
				_save(SLOT_MAIN)
				get_viewport().set_input_as_handled()
				return
			KEY_L:
				_load(SLOT_MAIN)
				get_viewport().set_input_as_handled()
				return
			KEY_H:
				_toggle_history()
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("ui_accept"):
			advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		advance()
		get_viewport().set_input_as_handled()
