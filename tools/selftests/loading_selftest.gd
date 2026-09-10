extends SceneTree
## 加载界面自检（窗口模式，要 save_png）：
##  1) 没盖加载层时，地形仍一口建完（保持老测试"两帧后可用"的时序约定）
##  2) 盖着加载层时，地形改成分片建：网格要等好几帧才填上，其间进度值一档档往上走
##  3) 覆盖层淡入到位、卡片每帧被驱动（星轮真的在转）、百分比跟着推进
##  4) 世界建完后覆盖层淡出并自毁，不会留在树上挡操作
## 注意：分片版每片之间 await 一个物理帧，所以"多少帧才铺完"本身就是分片是否生效的证据。

const GAME_SCENE := "res://scenes/main.tscn"
const GRID_N := 129                   # terrain.segments(128) + 1

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _grid_size(w: Node) -> int:
	return int((w.get_node("Ground").get("_grid") as PackedFloat32Array).size())


## 覆盖层的百分比文字；淡出收尾后标签已被清掉，这里返回空串而不是崩
func _pct_text() -> String:
	var l: Label = LoadingUI._pct
	return "" if l == null or not is_instance_valid(l) else String(l.text)


## 卡片自己的动画时钟：只在 _process 里累加，能证明覆盖层真的拿到了帧
func _anim(card: Node) -> float:
	return float(card.get("_t"))


func _run() -> void:
	# ---- 1. 没有加载层：仍走一口建完的老路 ----
	chk(not bool(LoadingUI.active()), "开局没有加载层")
	var a: PackedScene = load(GAME_SCENE)
	var w1 := a.instantiate()
	w1.get_node("Ground").set("seed_value", 88120)
	root.add_child(w1)
	await _frames(4)
	chk(_grid_size(w1) == GRID_N * GRID_N,
		"没有加载层时 4 个物理帧内碰撞网格已就绪（实测 %d 个高度）" % _grid_size(w1))
	w1.queue_free()
	await _frames(4)

	# ---- 2. 盖上加载层：分片建 + 进度推进 ----
	LoadingUI.show("正在读取素材…")
	await _frames(2)
	chk(bool(LoadingUI.active()), "show() 之后覆盖层在树上")
	var layer: CanvasLayer = LoadingUI._layer
	var dim: Control = LoadingUI._dim
	var card: Node = LoadingUI._card
	# 覆盖层的淡入与动画都挂在 _process（空闲帧）上，等物理帧可能一口气跑好几个而一帧都不画
	for _i in 20:
		await process_frame
	chk(float(dim.modulate.a) > 0.95, "覆盖层淡入到位（alpha %.2f）" % float(dim.modulate.a))
	LoadingUI.stage(0.12, "正在读取素材 1/5")
	var anim0 := _anim(card)
	for _i in 5:
		await process_frame
	chk(_anim(card) > anim0 + 0.02, "画面每帧都在被驱动（动画时钟 %.3f → %.3f）" % [anim0, _anim(card)])
	var pct0 := _pct_text()

	var b: PackedScene = load(GAME_SCENE)
	var w2 := b.instantiate()
	w2.get_node("Ground").set("seed_value", 88120)
	LoadingUI.stage(0.35, "正在生成世界…")
	root.add_child(w2)
	var frames := 0
	var levels := {}
	var pct_last := pct0
	while frames < 400 and _grid_size(w2) == 0:
		await physics_frame
		frames += 1
		levels[int(roundf(float(card.get("target")) * 100.0))] = true
		var p := _pct_text()
		if p != "":
			pct_last = p
		if frames == 12:
			_snap("loading_mid")          # 分片进行中：肉眼确认星轮与进度条长什么样
	chk(frames > 4, "碰撞网格不是一口气在第一帧建成的（用了 %d 个物理帧）" % frames)
	chk(levels.size() >= 6, "分片期间进度值一档档往上走（看到 %d 个不同档位）" % levels.size())
	chk(_grid_size(w2) == GRID_N * GRID_N, "网格最终铺满（%d 个高度）" % _grid_size(w2))

	# 等三角面 + 物理体也建完、覆盖层开始淡出
	var waited := 0
	while waited < 400 and bool(LoadingUI.active()):
		await physics_frame
		waited += 1
	chk(_grid_size(w2) == GRID_N * GRID_N, "世界仍在正常构建（贴物/小地图要用的网格在）")
	chk(pct_last != pct0 and pct_last != "0%" and pct_last != "",
		"百分比跟着推进（%s → %s）" % [pct0, pct_last])
	var waited2 := 0
	while waited2 < 200 and is_instance_valid(layer):
		await process_frame
		waited2 += 1
	chk(not bool(LoadingUI.active()), "建完世界后覆盖层收走")
	chk(not is_instance_valid(layer), "覆盖层已从树上释放，不会挡住操作（多等 %d 空闲帧）" % waited2)

	# 出图确认（窗口模式下才有纹理）
	_snap("loading_after")
	w2.queue_free()
	await _frames(4)

	# ---- 5. 真实入口：主菜单点「新游戏」（用户抱怨的就是这条路径）----
	var m: PackedScene = load("res://scenes/menu.tscn")
	var menu := m.instantiate()
	root.add_child(menu)
	for _i in 20:
		await process_frame
	chk(bool(menu.is_inside_tree()) and bool(menu.has_method("_on_new_game")), "主菜单已在树上")
	menu.call("_on_new_game")                 # 等价于点按钮（内部是协程，自行往下跑）
	var up := false
	var best := 0.0
	for _i in 600:
		await process_frame
		if bool(LoadingUI.active()):
			up = true
		# 读静态目标值（卡片可能在某一帧里被建了又拆，只盯卡片会漏看峰值）
		best = maxf(best, float(LoadingUI._target))
		var card2: Node = LoadingUI._card
		if card2 != null and is_instance_valid(card2):
			best = maxf(best, float(card2.get("target")))
		if _scene_up("Main") and best > 0.9:
			break
	chk(up, "点「新游戏」立刻盖上加载层（不是黑屏干等）")
	chk(best > 0.9, "覆盖层进度一路推到 %.0f%%" % (best * 100.0))
	chk(_scene_up("Main"), "确实切进了游戏场景（换场景由菜单里的后台加载完成）")
	_snap("loading_real_mid")
	# 切场景发生在世界建完之前：接着等覆盖层自己淡出
	for _i in 600:
		await process_frame
		if not bool(LoadingUI.active()):
			break
	chk(not bool(LoadingUI.active()), "世界建完后覆盖层自己淡出，不挡操作")
	_snap("loading_real_after")
	_done()


## --script 模式下没有"当前场景"这回事，只能自己到 root 名下找同名根节点
func _scene_up(nm: String) -> bool:
	for c in root.get_children():
		if String(c.name) == nm and c != null and is_instance_valid(c):
			return true
	return false


func _snap(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		chk(false, "%s：拿不到视口纹理（必须窗口模式跑）" % name)
		return
	img.save_png("user://%s.png" % name)
	print("  截图 | %s.png" % name)


func _done() -> void:
	print("\n== 加载界面自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
