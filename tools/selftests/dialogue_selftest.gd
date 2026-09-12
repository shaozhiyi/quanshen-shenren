extends SceneTree
## 对话框自检（窗口模式，要 save_png）：验证数据驱动的对话引擎
##  1) play(id) 能取到 SCRIPTS 里的段落并显示
##  2) 变量占位 {game_title}/{player_name} 被 VARS 正确替换
##  3) opts.vars 能临时覆盖变量
##  4) 打字机逐字显示（帧间文本变长）；打字中 advance() 瞬间出整行；再 advance() 进下一句
##  5) 走完全部台词后 finished、隐藏、on_done 回调触发
##  6) 截图肉眼确认样式

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _idle(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var dlg: Node = root.get_node_or_null("Dialogue")
	chk(dlg != null, "autoload Dialogue 已加载")
	if dlg == null:
		_done()
		return

	var done_flag := {"v": false}
	dlg.play("示例·开场", {"pause": false, "on_done": func(): done_flag["v"] = true})
	await _idle(2)
	chk(bool(dlg.is_showing()), "play 后正在显示")
	chk(bool(dlg.visible), "play 后对话框可见")

	# 第一行：who 为空（不显示名字），text 里的 {game_title}/{mode} 被替换
	var full0 := String(dlg.get("_full"))
	chk(full0.contains("全是神人") and full0.contains("正经模式"),
		"第1行占位符已替换（%s）" % full0)
	chk(not full0.contains("{"), "第1行没有残留未替换的 { }")
	chk(not bool(dlg.get("_who").visible), "旁白行（who 空）不显示名字")

	# 打字机：整行较长时，逐帧文本变长
	var lbl: Label = dlg.get("_text")
	var len_a := String(lbl.text).length()
	await _idle(3)
	var len_b := String(lbl.text).length()
	chk(len_b > len_a, "打字机逐字显示（%d → %d 字）" % [len_a, len_b])

	# 打字中 advance() → 瞬间出整行
	dlg.call("advance")
	await _idle(1)
	chk(String(lbl.text) == full0, "打字中 advance() 瞬间补全整行")

	# 截图：停在第 1 行整行显示时
	_snap("dialogue_line1")

	# 再 advance 进第 2 行
	dlg.call("advance")
	await _idle(1)
	var full1 := String(dlg.get("_full"))
	chk(full1.contains("国道") and full1 != full0, "advance 进入第 2 句（%s）" % full1)
	chk(bool(dlg.get("_who").visible) and String(dlg.get("_who").text) == "旁白", "第2句显示说话人『旁白』")

	# 走完剩余台词 → 结束、隐藏、回调
	var guard := 0
	while bool(dlg.is_showing()) and guard < 60:
		dlg.call("advance")
		await _idle(2)
		guard += 1
	chk(not bool(dlg.is_showing()), "走完全部台词后自动结束")
	chk(not bool(dlg.visible), "结束后对话框隐藏")
	chk(bool(done_flag["v"]), "on_done 回调被触发")

	# opts.vars 临时覆盖：把 {player_name} 换成张三
	dlg.play("示例·开场", {"pause": false, "vars": {"player_name": "张三"}})
	await _idle(1)
	var saw_name := false
	var g2 := 0
	while bool(dlg.is_showing()) and g2 < 20:
		var f := String(dlg.get("_full"))
		if f.contains("张三"):
			saw_name = true
		dlg.call("advance")
		await _idle(2)
		g2 += 1
	chk(saw_name, "opts.vars 覆盖了 {player_name} → 显示『张三』")
	chk(not bool(dlg.is_showing()), "第二段也正常结束")

	# ---- 底部功能条 ----
	var bar: Node = dlg.get("_bar")
	chk(bar != null and _count_buttons(bar) == 7,
		"功能条有 7 个按钮（实测 %d）" % (0 if bar == null else _count_buttons(bar)))

	dlg.play("示例·开场", {"pause": false})
	await _idle(1)
	dlg.call("_toggle_auto")
	chk(bool(dlg.get("_auto")), "『自动』可开启")
	dlg.call("_toggle_auto")
	chk(not bool(dlg.get("_auto")), "『自动』可关闭")

	dlg.call("_toggle_history")
	await _idle(1)
	chk(bool(dlg.get("_history_open")) and bool(dlg.get("_log_panel").visible), "『历史』打开回看面板")
	dlg.call("_toggle_history")
	chk(not bool(dlg.get("_history_open")), "『历史』可关闭")

	# 存档 → stop → 读档，应恢复到存档时的进度
	dlg.call("advance")   # 补全当前行
	await _idle(1)
	dlg.call("advance")   # 进入第 2 句
	await _idle(1)
	var idx_before := int(dlg.get("_idx"))
	dlg.call("_save", "test")
	dlg.call("stop")
	chk(not bool(dlg.is_showing()), "stop 后结束")
	dlg.call("_load", "test")
	await _idle(1)
	chk(bool(dlg.is_showing()), "读档后重新进入播放")
	chk(int(dlg.get("_idx")) == idx_before,
		"读档恢复到存档进度（index=%d，存档时=%d）" % [int(dlg.get("_idx")), idx_before])
	_snap("dialogue_bar")
	dlg.call("stop")

	_done()


func _count_buttons(box: Node) -> int:
	var n := 0
	for c in box.get_children():
		if c is Button:
			n += 1
	return n


func _snap(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		chk(false, "%s：拿不到视口纹理（必须窗口模式跑）" % name)
		return
	img.save_png("user://%s.png" % name)
	print("  截图 | %s.png" % name)


func _done() -> void:
	print("\n== 对话框自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
