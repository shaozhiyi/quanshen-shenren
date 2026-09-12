extends CanvasLayer
## 对话框引擎（全局 autoload：Dialogue）。数据驱动的通用剧情演出层。
## 台词内容全部在 scripts/dialogue_data.gd 里用变量维护，这里只管播放。
##
## 对外接口：
##   Dialogue.play(id_or_lines, opts)   # opts: {vars, speed, pause, on_done}
##   Dialogue.is_showing() -> bool
##   Dialogue.advance()                 # 手动推进（打字中=瞬间显示整行；否则下一句）
##   Dialogue.stop()                    # 立即结束
## 信号：started / line_shown(index) / finished

signal started
signal line_shown(index: int)
signal finished

const DATA := preload("res://scripts/dialogue_data.gd")

var _root: Control
var _panel: Panel
var _who: Label
var _text: Label
var _hint: Label

var _lines: Array = []
var _idx := -1
var _vars := {}
var _full := ""          # 当前行替换占位符后的完整文本
var _typed := 0.0        # 已显示的字符数（打字机进度）
var _speed := 34.0
var _active := false
var _pause := true
var _on_done := Callable()

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
	_panel.anchor_top = 0.70
	_panel.anchor_bottom = 0.955
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = 0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.93)
	sb.border_color = Color(0.62, 0.55, 0.32, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_panel)

	_who = Label.new()
	_who.anchor_left = 0.0
	_who.anchor_right = 1.0
	_who.offset_left = 26
	_who.offset_top = 14
	_who.offset_bottom = 42
	_who.add_theme_font_size_override("font_size", 20)
	_who.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	_who.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.02, 0.9))
	_who.add_theme_constant_override("outline_size", 6)
	_panel.add_child(_who)

	_text = Label.new()
	_text.anchor_left = 0.0
	_text.anchor_right = 1.0
	_text.anchor_top = 0.0
	_text.anchor_bottom = 1.0
	_text.offset_left = 26
	_text.offset_right = -26
	_text.offset_top = 50
	_text.offset_bottom = -18
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
	_hint.offset_top = -34
	_hint.offset_right = -18
	_hint.offset_bottom = -12
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	_hint.visible = false
	_panel.add_child(_hint)

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
	_active = true
	visible = true
	if _pause:
		get_tree().paused = true
	started.emit()
	_next()

func is_showing() -> bool:
	return _active

func advance() -> void:
	if not _active:
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
	if _idx >= _lines.size():
		_close()
		return
	var line: Dictionary = _lines[_idx]
	_who.text = _resolve(String(line.get("who", "")))
	_who.visible = not String(_who.text).is_empty()
	_full = _resolve(String(line.get("text", "")))
	_typed = 0.0
	_hint.visible = false
	_render()
	line_shown.emit(_idx)

func _close() -> void:
	_active = false
	visible = false
	_hint.visible = false
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
	if not _active:
		return
	if _typed < float(_full.length()):
		_typed = minf(_typed + _speed * delta, float(_full.length()))
		_render()

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	var accept := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ui_accept"):
			accept = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept = true
	elif event.is_action_pressed("ui_accept"):
		accept = true
	if accept:
		advance()
		get_viewport().set_input_as_handled()
