extends SceneTree
## 真实开局链路自检：走菜单那条"分帧进场景"的路（LoadingUI.enter_game），
## 然后检查跨节点引用与击败奖励是否真的通。
##
## 存在理由：其余 20 多份自检都是 `root.add_child(main.tscn 实例)`，一次性进树，
## 兄弟节点在 _ready 时全都已在树上；而游戏里现在是一个节点一帧地挂回来，
## Player 的 _ready 比 HUD/Inventory 早一帧 —— 于是 player._inv 绑不到，
## 击败野生狗奶的掉落与掉落箱回收全部静默失效（用户报的 bug）。这类"跨节点引用"
## 只有走真实链路才测得出来，所以单独一份，且刻意不走近路。

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


func _run() -> void:
	SaveManager.stage_new_game(88131)
	var m: PackedScene = load("res://scenes/menu.tscn")
	var menu := m.instantiate()
	root.add_child(menu)
	await _idle(20)
	menu.call("_on_new_game")                 # 等价于点「新游戏」：后台加载 + 分帧进场景
	var w: Node = await _wait_main(900)
	if w == null:
		chk(false, "没能切进游戏场景")
		_done()
		return
	await _idle(30)                           # 让地形分片建完、覆盖层淡出
	var player := w.get_node("Player")
	var hud := w.get_node("HUD")
	var inv: Node = hud.get_node("Inventory")

	# ---- 1. 跨节点引用（分帧进场景最容易踩空的地方）----
	chk(player != null and bool(player.is_inside_tree()), "Player 在树上")
	chk(player.get("_inv") != null, "player._inv 已绑到 HUD/Inventory（本次回归点）")
	chk(hud.get("_player") != null, "hud._player 已绑")
	chk(inv.get("_player") != null, "Inventory._player 已绑")
	chk(player.get("_field") != null, "player._field 已绑 BossField")
	chk((player.call("bosses") as Array).size() == 2, "名册两只 BOSS 都生成了")
	chk(not bool(LoadingUI.active()), "加载层已收走，不会挡住操作")

	# ---- 2. 掉落箱回收（同样依赖 player._inv 那条引用）----
	var inv_before: int = int(inv.call("count_of", "dogmilk"))
	player.call("spawn_drop_box", "dogmilk", 2)
	await _idle(3)
	var boxes: Array = get_nodes_in_group("drop_box")
	chk(boxes.size() > 0, "地上有掉落箱")
	var box: Node = boxes[boxes.size() - 1]
	box.global_position = player.global_position + Vector3(0.5, 0.0, 0.5)
	await _idle(2)
	chk(bool(player.call("_try_pick_box")), "按 E 能回收掉落箱")
	chk(int(inv.call("count_of", "dogmilk")) == inv_before + 2,
		"回收数量正确（%d → %d）" % [inv_before, int(inv.call("count_of", "dogmilk"))])

	# ---- 3. 进空间击败野生狗奶必须真的发奖 ----
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
	var before_milk: int = int(inv.call("count_of", "dogmilk"))
	var before_stone: int = int(inv.call("count_of", "stone"))
	var before_kills: int = int(player.get("kills"))
	milk.call("take_damage", 999999)          # 空间内可直接打死，走同一条 _die → died
	await _idle(2)
	var after_milk: int = int(inv.call("count_of", "dogmilk"))
	var after_stone: int = int(inv.call("count_of", "stone"))
	var want: int = int(milk.call("reward_count"))
	chk(int(player.get("kills")) == before_kills + 1, "击杀数 +1")
	chk(after_milk == before_milk + want,
		"击败野生狗奶 → 狗奶 ×%d 进背包（%d → %d）" % [want, before_milk, after_milk])
	chk(after_stone >= before_stone + 1,
		"必掉 1 块强化石（%d → %d）" % [before_stone, after_stone])
	_done()


func _wait_main(limit: int) -> Node:
	for _i in limit:
		await process_frame
		var w := _find_root("Main")
		if w != null:
			return w
	return null


func _done() -> void:
	print("\n== 开局链路自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
