extends SceneTree
## 播报提示自检：走真实开局链路（菜单 → 分帧进场景），进空间打两下、再打死，
## 核对文案、条数上限、淘汰顺序、位置（血条右侧、不压小地图、四行铺到"C 切换弓箭"那一行）。

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


func _find_root(nm: String) -> Node:
	for c in root.get_children():
		if String(c.name) == nm:
			return c
	return null


func _texts(hud: Node) -> Array[String]:
	var out: Array[String] = []
	for item in hud.get("_feed_lines"):
		out.append(String((item.get("label") as Label).text))
	return out


func _run() -> void:
	SaveManager.stage_new_game(20260905)
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await _idle(20)
	menu.call("_on_new_game")
	SaveManager.pending_seed = 20260905
	var w: Node = null
	for _i in 900:
		await process_frame
		w = _find_root("Main")
		if w != null:
			break
	if w == null:
		chk(false, "没能切进游戏场景")
		_done()
		return
	await _idle(40)
	var player: Node = w.get_node("Player")
	var hud: Node = w.get_node("HUD")
	var ground: Node = w.get_node("Ground")

	# ---- 1. 容器位置：血条右侧、不压小地图 ----
	var feed: Control = hud.get("_feed")
	chk(feed != null, "播报容器已建出")
	if feed == null:
		_done()
		return
	var bar_pos: Vector2 = hud.get("bar_position")
	var bar_sz: Vector2 = hud.get("bar_size")
	chk(feed.position.x > bar_pos.x + bar_sz.x - 1.0,
		"起点在血条右侧（x=%.0f，血条右沿 %.0f）" % [feed.position.x, bar_pos.x + bar_sz.x])
	chk(absf(feed.position.y - bar_pos.y) < 8.0,
		"顶部与血条齐平（y=%.0f vs %.0f）" % [feed.position.y, bar_pos.y])
	var max_x: float = hud.get("feed_line_width")
	var mm_pos: Vector2 = hud.get("minimap_position")
	chk(feed.position.x + max_x < mm_pos.x,
		"最长一条也不压到小地图（%.0f < %.0f）" % [feed.position.x + max_x, mm_pos.x])
	var lw: float = hud.get("feed_line_width")
	chk(lw > bar_sz.x * 0.5 and lw < bar_sz.x * 0.75,
		"每条长度 %.0f 米 = 血条 %.0f 的一半多一点" % [lw, bar_sz.x])
	var block_h: float = 4.0 * (float(hud.get("feed_line_height")) + float(hud.get("feed_gap")))
	chk(feed.position.y + block_h <= 140.0,
		"四条总高 %.0f 铺到「C 切换弓箭」那一行（到 y=%.0f）" % [block_h, feed.position.y + block_h])

	# ---- 2. 进空间打两下：每次击中播一条，带武器名 ----
	var milk: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "dogmilk":
			milk = b
	chk(milk != null, "找到野生狗奶")
	if milk == null:
		_done()
		return
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0,
		milk.global_position.z + 8.0)
	await _idle(2)
	player.call("_try_interact_boss")
	await _idle(10)
	chk(bool(player.call("in_arena")), "已进入野生狗奶空间")
	milk.call("take_damage", 100, "剑")
	await _idle(2)
	var t1 := _texts(hud)
	chk(t1.size() == 1, "击中一次播一条（现在 %d 条）" % t1.size())
	chk(t1.size() == 1 and t1[0] == "你使用剑击中野生狗奶", "击中文案=%s" % str(t1))
	milk.call("take_damage", 100, "弓")
	await _idle(2)
	var t2 := _texts(hud)
	chk(t2.size() == 2 and t2[0] == "你使用弓击中野生狗奶",
		"新条目排在最上面（第 1 条=%s）" % str(t2))

	# ---- 3. 击杀 BOSS：只播"你击败了yy" ----
	milk.call("take_damage", 999999, "弓")
	await _idle(2)
	var t3 := _texts(hud)
	chk(t3.size() == 3, "击杀再补一条（共 %d 条）" % t3.size())
	chk(t3.size() == 3 and t3[0] == "你击败了野生狗奶", "击杀文案=%s" % str(t3))

	# ---- 4. 条数上限与淘汰顺序 ----
	for i in 10:
		hud.call("announce", "占位%d" % i, Color(1, 1, 1))
		await _idle(1)
	var t4 := _texts(hud)
	chk(t4.size() == int(hud.get("feed_max")),
		"最多只留 %d 条（现在 %d 条）" % [int(hud.get("feed_max")), t4.size()])
	var want_last := "占位9"
	chk(t4[0] == want_last, "最新一条在最前（%s）" % t4[0])
	var ok_order := t4.size() == 4 and t4[1] == "占位8" and t4[2] == "占位7" and t4[3] == "占位6"
	chk(ok_order, "超出的从最末尾（最旧）开始删：%s" % str(t4))
	var alive := 0
	for c in feed.get_children():
		if is_instance_valid(c):
			alive += 1
	chk(alive <= int(hud.get("feed_max")), "被删掉的标签确实从树上摘了（还剩 %d 个）" % alive)

	# ---- 5. 排版：从上到下 y 递增、每条高度一致 ----
	var ys: Array = []
	for item in hud.get("_feed_lines"):
		ys.append((item.get("label") as Control).position.y)
	var sorted_ok := true
	for i in range(1, ys.size()):
		if float(ys[i]) <= float(ys[i - 1]):
			sorted_ok = false
	chk(sorted_ok, "四行自上而下排开（y=%s）" % str(ys))

	# ---- 6. feed_life > 0 时按秒数自动消失 ----
	hud.set("feed_life", 0.2)
	await _idle(40)
	chk(_texts(hud).is_empty(), "设了存活秒数后过期自动清空（还剩 %d 条）" % _texts(hud).size())
	hud.set("feed_life", 0.0)

	# ---- 7. 只留击杀：关掉击中播报后不再刷命中 ----
	hud.set("feed_announce_hits", false)
	var before := _texts(hud).size()
	milk.call("respawn")
	await _idle(4)
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0,
		milk.global_position.z + 8.0)
	player.call("_try_interact_boss")
	await _idle(10)
	milk.call("take_damage", 50, "剑")
	await _idle(2)
	chk(_texts(hud).size() == before,
		"feed_announce_hits=false 时击中不播报（%d → %d）" % [before, _texts(hud).size()])
	chk(float(ground.get("terrain_seed")) == 20260905, "种子按指定值生效")
	_done()


func _done() -> void:
	print("\n== 播报自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
