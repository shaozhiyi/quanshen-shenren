extends SceneTree
## 两套坐标自检：大世界坐标 vs 战斗坐标
##  1) 大地图上 display_coords() == global_position，且 HUD 前缀是「世界」
##  2) 进 BOSS 空间（国道 / 纯白都试）→ 战斗坐标开局就是 (0,0,0)，前缀换成「战斗」
##  3) 战斗内跑 20 米：战斗坐标读 20，世界坐标仍是战场那套远端绝对值（两者互不污染）
##  4) 撤退后立刻回到世界坐标；再次开战原点重取，仍然从 0 开始
##  5) 场内死亡重生回到出生点 = 战斗坐标也回到 0（与"开战即为 0"一致）
## 必须窗口模式跑（要读 HUD 的 Label 文本）。

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _hud_label(w: Node) -> String:
	var hud := w.get_node_or_null("HUD")
	if hud == null:
		return ""
	var lb: Label = hud.get("_coord_label")
	return lb.text if lb != null else ""


## 把 "战斗 X: 0.0  Y: 20.0  Z: 0.0" 里的三个数按显示顺序取出来
func _nums(txt: String) -> Array[float]:
	var out: Array[float] = []
	for part in txt.split("  "):
		var i := part.find(":")
		if i >= 0:
			out.append(float(part.substr(i + 1).strip_edges()))
	return out


func _boss(player: Node, id: String) -> Node:
	for b in player.call("bosses"):
		if String(b.get("def_id")) == id:
			return b
	return null


func _run() -> void:
	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 88106)
	root.add_child(w)
	await _frames(30)
	var player := w.get_node("Player")
	var hw: Node = null
	var wht: Node = null
	for a in get_nodes_in_group("arena"):
		if String(a.call("theme_key")) == "highway":
			hw = a
		else:
			wht = a
	chk(hw != null and wht != null, "两套战场都在")

	# ---- 1. 大地图 = 世界坐标 ----
	chk(not bool(player.call("coords_are_battle")), "大地图上不是战斗坐标")
	var gp: Vector3 = player.global_position
	var dc: Vector3 = player.call("display_coords")
	chk(dc.distance_to(gp) < 0.001, "大地图 display_coords 就是 global_position")
	await _frames(3)
	chk(_hud_label(w).begins_with("世界"), "HUD 前缀「世界」（%s）" % _hud_label(w))

	# ---- 2. 进国道：开局 (0,0,0) ----
	var truck := _boss(player, "truck")
	player.global_position = Vector3(truck.global_position.x, truck.global_position.y + 1.0,
		truck.global_position.z + 8.0)
	await _frames(2)
	player.call("_enter_arena")
	await _frames(20)        # 出生悬空 0.15 米，等它真落地（原点会在校正一次）
	chk(bool(player.call("coords_are_battle")), "进国道后是战斗坐标")
	var dc2: Vector3 = player.call("display_coords")
	chk(dc2.length() < 0.01, "开战那一刻战斗坐标 = (0,0,0)（实测 %.3f）" % dc2.length())
	var org: Vector3 = player.call("battle_origin")
	var c: Vector3 = hw.call("center")
	chk(absf(org.z - c.z) < 400.0 and absf(org.z) > 1000.0,
		"战斗原点在世界坐标深处（z=%.0f），与战斗读数无关" % org.z)
	await _frames(3)
	chk(_hud_label(w).begins_with("战斗"), "HUD 前缀换成「战斗」（%s）" % _hud_label(w))

	# ---- 3. 战斗内跑 20 米：两套坐标各算各的 ----
	player.global_position = org + Vector3(0.0, 0.0, 20.0)
	var dc3: Vector3 = player.call("display_coords")
	chk(absf(dc3.z - 20.0) < 0.01 and absf(dc3.x) < 0.01,
		"跑出去 20 米 → 战斗坐标读 20（实测 %.2f）" % dc3.z)
	chk(player.global_position.z > 1000.0 or player.global_position.z < -1000.0,
		"世界坐标仍是战场那套绝对值（z=%.0f）" % player.global_position.z)


	# ---- 3b. 显示轴向：X=横、Y=纵（引擎 Z 前后）、Z=高（引擎 Y 上下）----
	await _frames(2)
	var n: Array[float] = _nums(_hud_label(w))
	chk(n.size() == 3, "HUD 三个数都解析到了（%s）" % _hud_label(w))
	chk(absf(n[0]) < 0.01 and absf(n[1] - 20.0) < 0.01,
		"沿路跑 20 米 → 读数 X=%.1f Y=%.1f（纵轴在第二位）" % [n[0], n[1]])
	chk(absf(n[2]) < 0.2, "站在地上 → 第三位（高）= %.1f" % n[2])
	player.global_position = org + Vector3(4.0, 3.0, 20.0)
	await _frames(1)
	var up: Array[float] = _nums(_hud_label(w))
	chk(absf(up[0] - 4.0) < 0.01 and absf(up[1] - 20.0) < 0.01 and absf(up[2] - 3.0) < 0.01,
		"抬高 3 米只有第三位变（X=%.1f Y=%.1f Z=%.1f）" % [up[0], up[1], up[2]])
	player.global_position = org + Vector3(0.0, 0.0, 20.0)

	# ---- 4. 撤退 → 回世界坐标；再开战 → 又从 0 起 ----
	player.call("_exit_arena")
	await _frames(3)
	chk(not bool(player.call("coords_are_battle")), "撤退后回到世界坐标")
	var back: Vector3 = player.call("display_coords")
	chk(back.distance_to(player.global_position) < 0.001, "撤退后 display_coords == global_position")
	chk(_hud_label(w).begins_with("世界"), "撤退后 HUD 前缀回到「世界」")

	player.global_position = Vector3(truck.global_position.x, truck.global_position.y + 1.0,
		truck.global_position.z + 8.0)
	await _frames(2)
	player.call("_enter_arena")
	await _frames(20)
	var dc4: Vector3 = player.call("display_coords")
	chk(dc4.length() < 0.01, "再次开战原点重取，仍然从 (0,0,0) 开始")
	var org2: Vector3 = player.call("battle_origin")
	chk(absf(org2.x - (c.x + 12.5)) < 1.0,
		"原点取的是本次出生点（右幅车道 x=%.1f，上一次 %.0f → 这一次 %.0f）" % [org2.x - c.x, org.z, org2.z])

	# ---- 5. 场内死亡重生：回到出生点 = 战斗坐标 0 ----
	player.global_position = org2 + Vector3(0.0, 0.0, 33.0)
	var far: Vector3 = player.call("display_coords")
	chk(absf(far.z - 33.0) < 0.01, "跑远后战斗坐标 = %.1f" % far.z)
	player.call("_exit_arena")
	await _frames(2)

	# ---- 6. 纯白战场同理，且两套战场的原点互不串 ----
	var milk := _boss(player, "dogmilk")
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0,
		milk.global_position.z + 8.0)
	await _frames(2)
	player.call("_enter_arena")
	await _frames(20)
	chk(bool(player.call("coords_are_battle")), "进纯白空间也是战斗坐标")
	var dc5: Vector3 = player.call("display_coords")
	chk(dc5.length() < 0.01, "纯白空间开局同样 (0,0,0)")
	var wc: Vector3 = wht.call("center")
	var o3: Vector3 = player.call("battle_origin")
	chk(absf(o3.x - wc.x) < 60.0 and absf(o3.z - wc.z) < 60.0,
		"纯白原点贴着纯白战场中心（不是国道那个）")
	player.call("_exit_arena")
	await _frames(2)
	_done()


func _done() -> void:
	print("\n== 坐标自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
