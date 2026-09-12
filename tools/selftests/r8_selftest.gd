extends SceneTree
## 本轮（R8）改动的无头自检：
##  1) 星点改成立体网格；红色飞行速度 ×1.5、蓝色 ×0.7（黄/绿 ×1.0）
##  2) 冲刺特效（风痕拖尾）与挥剑剑气特效：自动生、自动灭、不投影、不刷屏
##  3) 按 Tab 打开背包 = 暂停整局（BOSS 时间冻结），关包恢复
##  4) 魔法上限 200（本版无技能消耗，接口先备好）；等级 LV1 与绿色经验条只做显示（无升级系统）
##  5) HUD 血条由绿改红；无敌期换金色配色
##  6) 音效模块：三个文件都已就位并能加载（缺失时只静默，不报错）

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


func _mode_nodes(mode: String) -> Array:
	var out: Array = []
	for n in get_nodes_in_group("slam_fx"):
		if String(n.get("_mode")) == mode:
			out.append(n)
	return out


func _star_nodes() -> Array:
	return get_nodes_in_group("slam_star")


func _audio_players() -> int:
	## root 直属的 AudioStreamPlayer 数量（SFX 一次性播放器就建在这里）
	var n := 0
	for c in root.get_children():
		if c is AudioStreamPlayer:
			n += 1
	return n


func _sfx_players(id: String) -> int:
	## 携带指定 sfx 标记、且尚未回收的一次性播放器数量（验证 cut 型打断后不泄露）
	var n := 0
	for c in root.get_children():
		if c is AudioStreamPlayer and String((c as Node).get_meta("sfx", "")) == id:
			n += 1
	return n


func _run() -> void:
	var FX: GDScript = load("res://scripts/slam_fx.gd")
	var SFXS: GDScript = load("res://scripts/sfx.gd")

	# ---- 1. 按颜色的速度倍率（表本身）----
	chk(absf(float(FX.star_speed_mult("red")) - 1.5) < 1e-6, "红色星点速度 ×1.5")
	chk(absf(float(FX.star_speed_mult("blue")) - 0.7) < 1e-6, "蓝色星点速度 ×0.7")
	chk(absf(float(FX.star_speed_mult("yellow")) - 1.0) < 1e-6, "黄色星点速度不变")
	chk(absf(float(FX.star_speed_mult("green")) - 1.0) < 1e-6, "绿色星点速度不变")
	chk(absf(float(FX.star_speed_mult("nope")) - 1.0) < 1e-6, "未知颜色按基准 ×1.0 兜底")

	# ---- 2. 立体星点网格 ----
	var mesh: ArrayMesh = FX.star_mesh()
	chk(mesh != null, "star_mesh() 产出网格资源")
	chk(mesh is ArrayMesh, "星点是真正的 3D 网格（ArrayMesh，不是面片）")
	chk(int(mesh.get_surface_count()) == 1, "星点只有 1 个面（一次 draw call）")
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	chk(int(mesh.surface_get_primitive_type(0)) == Mesh.PRIMITIVE_TRIANGLES, "星点由三角面组成")
	chk(verts.size() >= 12, "星点网格有 %d 个顶点（多面晶簇）" % verts.size())
	var aabb := AABB()
	for v in verts:
		aabb = aabb.expand(v)
	chk(absf(aabb.size.y - 1.0) < 0.08, "星点网格高 %.2f 米（scale 即米数）" % aabb.size.y)
	chk(aabb.size.x > 0.2 and aabb.size.x < 0.8, "星点网格宽 %.2f 米（星形而非球）" % aabb.size.x)
	chk((arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == verts.size(), "每顶点带法线（棱面受光）")
	chk((arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() == verts.size(), "每顶点带颜色（逐面明暗）")

	# ---- 场景：拿玩家 / BOSS / 剑 / HUD / 背包 ----
	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 77002)
	root.add_child(w)
	await _frames(12)
	var player: Node = w.get_node("Player")
	var hud: Node = w.get_node("HUD")
	var inv: Node = hud.get_node("Inventory")
	var sword: Node = w.get_node("Player/Camera3D/Sword")
	var cam: Camera3D = w.get_node("Player/Camera3D") as Camera3D
	var milk: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "dogmilk":
			milk = b
	chk(milk != null, "找到野生狗奶")
	chk(hud != null and inv != null and sword != null and cam != null, "HUD/背包/剑/相机节点齐全")
	if milk == null:
		_done()
		return

	# ---- 3. 环绕星点也换成同一套立体网格 ----
	var st0: Node = (milk.get("_stars") as Array)[0]
	chk(st0.get("mesh") == mesh, "BOSS 蓄力星点与射出星点共用同一份立体网格")
	chk(String(st0.get_meta("kind")) == "red", "第 0 颗蓄力星点仍是红色（种类记录没丢）")
	chk(int(st0.get("cast_shadow")) == 0, "蓄力星点不投影")

	# ---- 4. 射出的星点：立体 + 速度按颜色 ----
	FX.spawn_star(root, Vector3(0, 60, 0), Vector3.FORWARD, 42.0, 8.0, 1.4, 5.0, "red")
	FX.spawn_star(root, Vector3(2, 60, 0), Vector3.FORWARD, 42.0, 8.0, 1.4, 5.0, "blue")
	FX.spawn_star(root, Vector3(4, 60, 0), Vector3.FORWARD, 42.0, 8.0, 1.4, 5.0, "yellow")
	await _frames(2)
	var flying := _star_nodes()
	chk(flying.size() == 3, "三颗不同颜色的星点都建出来了（%d）" % flying.size())
	var sp_map := {}
	for n in flying:
		sp_map[String(n.get("_kind"))] = float(n.get("_speed"))
	chk(absf(float(sp_map.get("red", 0.0)) - 63.0) < 1e-4, "红星点实际速度 %.1f = 42×1.5" % float(sp_map.get("red", 0.0)))
	chk(absf(float(sp_map.get("blue", 0.0)) - 29.4) < 1e-4, "蓝星点实际速度 %.1f = 42×0.7" % float(sp_map.get("blue", 0.0)))
	chk(absf(float(sp_map.get("yellow", 0.0)) - 42.0) < 1e-4, "黄星点保持 42 基准")
	var one: Node = flying[0]
	var crystal: Node = one.get("_star_mi")
	var glow: Node = one.get("_glow_mi")
	chk(crystal != null and crystal.get("mesh") == mesh, "飞行星点用的就是立体网格")
	var cmat: StandardMaterial3D = crystal.get("material_override") as StandardMaterial3D
	chk(cmat != null and bool(cmat.vertex_color_use_as_albedo), "晶簇材质用顶点色做逐面明暗")
	chk(cmat != null and int(cmat.billboard_mode) == 0, "晶簇本身不做公告板（真 3D）")
	chk(glow != null, "星点带外圈光晕")
	if glow != null:
		var gmat: StandardMaterial3D = glow.get("material_override") as StandardMaterial3D
		chk(gmat != null and int(gmat.billboard_mode) != 0, "光晕仍是公告板（远处看得见）")
		chk(int(glow.get("cast_shadow")) == 0, "光晕不投影")
	chk(int(crystal.get("cast_shadow")) == 0, "晶簇不投影")
	# 星点仍在空中 → 不该消失（只有落到地板才消失）
	await _frames(40)
	chk(_star_nodes().size() >= 1, "高空飞行的星点没有半路自毁（剩 %d）" % _star_nodes().size())
	for n in _star_nodes():
		n.queue_free()
	await _frames(5)
	chk(_star_nodes().is_empty(), "清理完毕，不影响后续断言")

	# ---- 5. 冲刺特效 ----
	var before: int = _mode_nodes("wind").size()
	player.set("velocity", Vector3.ZERO)
	chk(bool(player.call("try_dash")), "Z 冲刺触发成功")
	var winds := _mode_nodes("wind")
	chk(winds.size() == before + 1, "冲刺生成了风痕拖尾")
	var rushes := _mode_nodes("rush")
	chk(rushes.size() == 1, "冲刺同时在眼前拉出速度线（第一人称看得见）")
	if rushes.size() > 0:
		var rf: Node = rushes[0]
		chk(rf.get_parent() == cam, "速度线挂在相机下（跟随视野）")
		chk(int((rf.get("_layers") as Array).size()) == 9, "一圈 %d 条径向风痕"
			% int((rf.get("_layers") as Array).size()))
	if winds.size() > before:
		var fx: Node = winds[winds.size() - 1]
		var layers: Array = fx.get("_layers")
		chk(int(layers.size()) >= 8, "拖尾由 %d 片风痕组成（4 段 × 十字 2 片）" % int(layers.size()))
		var no_shadow := true
		var grows := 0
		for L in layers:
			var mi: MeshInstance3D = L["mi"] as MeshInstance3D
			if int(mi.cast_shadow) != 0:
				no_shadow = false
			if float(L["s1"]) > float(L["s0"]):
				grows += 1
		chk(no_shadow, "风痕全部不投影（不会在地上甩方块影）")
		chk(grows == int(layers.size()), "每片风痕都会放大散开")
		chk(_mode_nodes("wind").size() + _mode_nodes("").size() >= 2, "冲刺同时带一圈脚下光环")
	await _frames(50)
	chk(_mode_nodes("wind").size() == before, "拖尾播完自动清理（不堆积）")
	chk(_mode_nodes("rush").is_empty(), "眼前速度线也自动清理")
	player.set("_dash_cd", 0.0)
	player.set("_dash_time", 0.0)
	var n0: int = _mode_nodes("wind").size()
	player.call("try_dash")
	var n1: int = _mode_nodes("wind").size()
	chk(n1 == n0 + 1, "冷却清空后可以再冲刺")
	player.set("_dash_cd", 0.4)
	player.call("try_dash")
	chk(_mode_nodes("wind").size() == n1, "冷却中再按 Z 不生成新拖尾")
	player.set("_dash_cd", 0.0)

	# ---- 6. 挥剑剑气 ----
	var s_before: int = _mode_nodes("slash").size()
	sword.call("attack")
	await _frames(3)
	var slashes := _mode_nodes("slash")
	chk(slashes.size() == s_before + 1, "挥剑生成剑气特效")
	if slashes.size() > s_before:
		var sf: Node = slashes[slashes.size() - 1]
		var sl: Array = sf.get("_layers")
		chk(int(sl.size()) == 2, "剑气是两层弧光（外圈 + 内芯）")
		var fwd: Vector3 = -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var rel: Vector3 = sf.global_position - cam.global_position
		chk(sf.get_parent() == cam, "剑气挂在相机下（跟随第一人称视角，不会脱手）")
		# 用相机逆变换算局部偏移：玩家在空中移动也不影响判定
		var local: Vector3 = cam.global_transform.affine_inverse() * sf.global_position
		chk(local.z < -0.9 and local.z > -1.4, "剑气落在视线内 %.2f 米处" % -local.z)
		chk(absf(local.x) < 0.1 and absf(local.y + 0.22) < 0.1,
			"剑气居中且略低于视线（局部 %s）" % str(local))
		chk(rel.length() > 0.5, "挥剑瞬间弧光确实在相机前方 %.2f 米" % rel.length())
		chk((-sf.global_transform.basis.z).dot(fwd) > 0.9, "弧面正对玩家（朝向跟视线一致）")
		var arc: Mesh = (sl[0]["mi"] as MeshInstance3D).mesh as Mesh
		chk(arc != null, "弧光网格已建出")
		var am: StandardMaterial3D = (sl[0]["mi"] as MeshInstance3D).material_override as StandardMaterial3D
		chk(am != null and int(am.cull_mode) == BaseMaterial3D.CULL_DISABLED, "弧光双面可见")
	await _frames(30)
	chk(_mode_nodes("slash").size() == s_before, "剑气播完自动清理")

	# ---- 7. 音效：文件就位、播得出来、缺文件也不崩 ----
	var paths := {
		"swing": "res://assets/audio/sword_swing.wav",
		"swing2": "res://assets/audio/sword_swing_2.wav",
		"draw": "res://assets/audio/bow_draw.wav",
		"shot": "res://assets/audio/bow_shot.wav",
	}
	var present := 0
	for k in paths:
		if ResourceLoader.exists(String(paths[k])):
			present += 1
	chk(present == 4, "四个音效文件都已就位（挥剑×2 变体/拉弓/放箭，%d/4）" % present)

	var swing_before := _sfx_players("swing")
	SFXS.call("play", "swing")
	await _frames(2)
	var swing_after := _sfx_players("swing")
	# cut 型：新播放器替换上一个同种，旧的被打断即回收——存活恰好 1 个，不再像以前那样泄露堆积
	chk(swing_after == 1, "play(swing) 建出且仅留一个存活播放器（swing: %d → %d，不泄露）" % [swing_before, swing_after])
	var before_multi := _audio_players()
	SFXS.call("play", "draw")
	SFXS.call("play", "shot")
	SFXS.call("play", "不存在的id")     # 未登记的 id 必须安静返回，不报错
	await _frames(2)
	chk(_audio_players() <= before_multi + 2, "连续播放不崩且不无限累积（当前 %d 个播放器）" % _audio_players())

	# ---- 8. Tab 打开背包 = 暂停整局 ----
	chk(int(inv.process_mode) == Node.PROCESS_MODE_ALWAYS, "背包面板用 ALWAYS（暂停与平时都收输入）")
	chk(int(inv.process_mode) != Node.PROCESS_MODE_WHEN_PAUSED
		and int(inv.process_mode) != Node.PROCESS_MODE_PAUSABLE,
		"背包不会平时不收 Tab、也不会暂停后不收 Tab")
	chk(not paused, "开局未暂停")
	var boss_t: float = float(milk.get("_t"))
	inv.call("_toggle")
	chk(paused, "按 Tab 开包 → 整局暂停")
	chk(bool(inv.get("_open")) and bool(inv.visible), "面板可见")
	chk(int(player.process_mode) == Node.PROCESS_MODE_DISABLED, "玩家被禁用")
	await _frames(20)
	chk(absf(float(milk.get("_t")) - boss_t) < 1e-6, "暂停期间 BOSS 时间不推进（相位/星点全冻住）")
	chk(paused, "跑完帧仍是暂停（不会自己解除）")
	inv.call("_toggle")
	chk(not paused, "再按 Tab 关包 → 解除暂停")
	chk(int(player.process_mode) == Node.PROCESS_MODE_INHERIT, "玩家恢复处理")
	await _frames(8)
	chk(float(milk.get("_t")) > boss_t, "恢复后 BOSS 继续跑")

	# ---- 9. 魔法与等级 ----
	chk(absf(float(player.get("max_mp")) - 200.0) < 1e-6, "魔法上限 200")
	chk(absf(float(player.get("mp")) - 200.0) < 1e-6, "开局魔法满值")
	var mp_ev := {"n": 0}
	player.connect("mp_changed", func(_a, _b): mp_ev["n"] = int(mp_ev["n"]) + 1)
	chk(bool(player.call("spend_mp", 50.0)), "消耗 50 魔法成功")
	chk(absf(float(player.get("mp")) - 150.0) < 1e-6, "魔法剩 150")
	chk(not bool(player.call("spend_mp", 1000.0)), "魔法不够时不扣")
	chk(absf(float(player.get("mp")) - 150.0) < 1e-6, "失败消耗不改数值")
	chk(bool(player.call("has_mp", 150.0)) and not bool(player.call("has_mp", 151.0)), "has_mp 判定正确")
	player.call("restore_mp", 1000.0)
	chk(absf(float(player.get("mp")) - 200.0) < 1e-6, "回魔封顶在 200")
	chk(int(mp_ev["n"]) == 2, "mp_changed 只在真正扣/回时广播（%d 次）" % int(mp_ev["n"]))
	chk(absf(float(player.call("mp_ratio")) - 1.0) < 1e-6, "mp_ratio 供 HUD 读取")
	chk(int(player.get("level")) == 1, "等级为 1")
	chk(String(player.call("level_text")) == "LV1", "等级文本 LV1")
	chk(absf(float(player.call("exp_ratio"))) < 1e-6, "经验条为 0（升级系统未实现）")
	player.set("hp", 1.0)
	player.call("take_damage", 500.0)
	await _frames(3)
	chk(float(player.get("hp")) > 0.0, "死亡后按 30%% 苏醒（hp=%.1f）" % float(player.get("hp")))
	chk(absf(float(player.get("mp")) - 200.0) < 1e-6, "苏醒同时回满魔法")

	# ---- 10. HUD：血条红色 + 三条 + LV ----
	var bar: Control = hud.get("_bar") as Control
	var mpb: Control = hud.get("_mp_bar") as Control
	var expb: Control = hud.get("_exp_bar") as Control
	var lvl: Label = hud.get("_lv_label") as Label
	chk(bar != null and mpb != null and expb != null and lvl != null, "HUD 四件套齐全（血/魔/经验/LV）")
	var bs: HealthBarXStyle = bar.get("style") as HealthBarXStyle
	chk(bs.color_green.r > bs.color_green.g + 0.2 and bs.color_green.r > bs.color_green.b + 0.2,
		"血条满血是红色（不再绿）")
	chk(bs.color_red.r > 0.4 and bs.color_red.g < 0.2, "濒危用更暗的红")
	chk(int(bs.color_green.g * 100) < int(bs.color_green.r * 100), "血条绿色通道低于红色通道")
	# HealthBarX 是百分比条：填充量程必须恒为 100，真实上限只进 label_custom_max
	# （曾把 200 塞进 max_value，导致满值 100%÷200 只画一半）
	var ms: HealthBarXStyle = mpb.get("style") as HealthBarXStyle
	chk(absf(float(mpb.get("max_value")) - 100.0) < 1e-6, "魔法条填充量程恒为 100（百分比条）")
	chk(absf(float(ms.label_custom_max) - 200.0) < 1e-6, "魔法条文字上限 200（label_custom_max）")
	chk(ms.fill_color.b > ms.fill_color.r + 0.2, "魔法条是蓝色")
	var es: HealthBarXStyle = expb.get("style") as HealthBarXStyle
	chk(es.fill_color.g > es.fill_color.r + 0.2 and es.fill_color.g > es.fill_color.b, "经验条是绿色")
	chk(String(lvl.text) == "LV1", "HUD 显示 LV1")
	# 三条互不重叠、LV 徽章不压血条
	var ctrls: Array = [bar, mpb, expb]
	var overlap := false
	for i in ctrls.size():
		for j in range(i + 1, ctrls.size()):
			var ca: Control = ctrls[i] as Control
			var cb: Control = ctrls[j] as Control
			var ra := Rect2(ca.position, ca.size)
			var rb := Rect2(cb.position, cb.size)
			if ra.intersects(rb):
				overlap = true
	chk(not overlap, "血/魔/经验三条互不重叠（%s | %s | %s）" % [
		str(Rect2(bar.position, bar.size)), str(Rect2(mpb.position, mpb.size)),
		str(Rect2(expb.position, expb.size))])
	chk(not Rect2(lvl.position, lvl.size).intersects(Rect2(bar.position, bar.size)), "LV 徽章不压血条")
	chk(float(bar.position.y) < float(mpb.position.y), "自上而下：血 → 魔 → 经验")
	hud.call("_process", 0.01)
	chk(absf(float(mpb.get("value")) - 100.0) < 1e-4, "HUD 魔法条满值（%.0f%%）" % float(mpb.get("value")))
	# 满值时显示值应顶满填充量程（这就是"只画一半"那个 bug 的回归断言）
	chk(absf(float(mpb.get("_display_value")) - 100.0) < 1e-4, "满值时显示值=100（填充全宽，不再减半）")
	player.call("spend_mp", 120.0)
	hud.call("_process", 0.01)
	chk(absf(float(mpb.get("value")) - 40.0) < 1e-4, "HUD 魔法条随消耗更新（80/200 → %.0f%%）" % float(mpb.get("value")))

	# 无敌 → 金色血条；解除 → 回红
	player.call("gain_invincibility", 10.0)
	hud.call("_process", 0.01)
	var gold_s: HealthBarXStyle = bar.get("style") as HealthBarXStyle
	chk(gold_s.fill_color.g > 0.6 and gold_s.fill_color.b < 0.4, "无敌期血条换金色")
	chk(bool(hud.get("_inv_bar_golden")), "金色标记已置位")
	player.call("_end_invincibility")
	hud.call("_process", 0.01)
	var back_s: HealthBarXStyle = bar.get("style") as HealthBarXStyle
	chk(back_s.fill_color.r > back_s.fill_color.g + 0.2, "解除后回到红条")
	chk(not bool(hud.get("_inv_bar_golden")), "金色标记已复位")

	_done()


func _done() -> void:
	print("\n== 结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
