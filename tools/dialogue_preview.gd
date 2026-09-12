extends SceneTree
## 对话预览工具：不进游戏，直接看某段剧情的实际演出（打字机/功能条/历史/存读都在）。
## 用法（配合根目录「预览对话.bat」）：
##   预览对话.bat          → 打印所有剧情名，预览第一段
##   预览对话.bat 2        → 按序号预览第 2 段（序号是 ASCII，走命令行最稳）
## 操作：回车/空格/左键 翻页；A 自动、S/L 存读、H 历史（同对话框）；Esc 退出。
## 想改台词只动 scripts/dialogue_data.gd，重跑本工具立刻看到效果。

const DATA := preload("res://scripts/dialogue_data.gd")

var _dlg: Node


func _initialize() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var tip := Label.new()
	tip.text = "对话预览 · 回车/点击翻页 · A自动 H历史 S/L存读 · Esc退出"
	tip.position = Vector2(16, 12)
	tip.add_theme_font_size_override("font_size", 16)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	layer.add_child(tip)

	var ids: Array = DATA.SCRIPTS.keys()
	print("[dialogue_preview] 可用剧情（按序号）：")
	for i in ids.size():
		print("   %d) %s" % [i + 1, String(ids[i])])

	var args := OS.get_cmdline_user_args()
	var pick := 0
	if not args.is_empty():
		var a := String(args[0])
		if a.is_valid_int():
			pick = a.to_int() - 1
		else:
			# 直接给了名字（注意：cmd 传中文可能乱码，优先用序号）
			var found := ids.find(a)
			pick = found if found >= 0 else 0
	pick = clampi(pick, 0, ids.size() - 1)
	var id := String(ids[pick])
	print("[dialogue_preview] 预览 #%d：%s" % [pick + 1, id])

	_dlg = root.get_node_or_null("Dialogue")
	if _dlg == null:
		push_error("[dialogue_preview] 找不到 autoload Dialogue")
		quit(1)
		return
	_dlg.finished.connect(func(): quit(0))
	_dlg.play(id, {"pause": false})


func _process(_delta: float) -> bool:
	if Input.is_action_just_pressed("ui_cancel"):
		quit(0)
		return true
	return false
