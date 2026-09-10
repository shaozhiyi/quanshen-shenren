extends SceneTree
## 新 BOSS「大运」无头自检：名册字段、三档血量 2000/2500/3000、暂无技能（不飞天不砸地
## 不射星点）、缓慢驶近 + 贴身光环、占位低模外观与碰撞盒，以及老 BOSS（野生狗奶）不受影响。

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


func _boss_by_id(bs: Array, id: String) -> Node:
	for b in bs:
		if String(b.get("def_id")) == id:
			return b
	return null


func _fallback_boss() -> Node:
	## 不入树地造一只"模型文件缺失"的重卡，验证外观自动回退到占位低模
	var BS: GDScript = load("res://scripts/boss.gd")
	var b: Node = BS.new()
	b.set("def_id", "truck")
	b.call("_load_def")
	b.set("_model_path", "res://assets/models/__not_here__.glb")
	b.set("_visual", Node3D.new())
	b.call("_build_visual")
	return b


func _run() -> void:
	var ROSTER: GDScript = load("res://scripts/boss_roster.gd")
	var d: Dictionary = ROSTER.def("truck")
	chk(not d.is_empty(), "名册里有 truck 条目")
	chk(String(d.get("name")) == "大运", "显示名 = 大运")
	var hps: Array = d.get("hp_by_diff", [])
	chk(hps.size() == 3 and float(hps[0]) == 2000.0 and float(hps[1]) == 2500.0 and float(hps[2]) == 3000.0,
		"三档血量 2000/2500/3000（实际 %s）" % str(hps))
	chk(bool(d.get("skills", true)) == false, "名册标记为暂无技能")
	chk(String(d.get("model")) == "res://assets/models/truck.glb", "模型直投槽 = assets/models/truck.glb")

	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	w.get_node("Ground").set("seed_value", 141421)
	root.add_child(w)
	await _frames(10)
	var player := w.get_node("Player")
	var bs: Array = player.call("bosses")
	chk(bs.size() == 2, "大地图生成 2 只 BOSS（实际 %d）" % bs.size())
	var truck: Node = _boss_by_id(bs, "truck")
	var milk: Node = _boss_by_id(bs, "dogmilk")
	chk(truck != null and milk != null, "按 def_id 找到重卡与狗奶")
	if truck == null:
		_done()
		return

	# ---- 1. 三档血量 ----
	for i in 3:
		truck.set("difficulty", i)
		truck.call("apply_difficulty")
		var want: float = [2000.0, 2500.0, 3000.0][i]
		chk(abs(float(truck.get("max_hp")) - want) < 0.001,
			"%s 档血量 = %d（实际 %d）" % [String(truck.call("difficulty_name")), int(want), int(truck.get("max_hp"))])
		chk(abs(float(truck.get("hp")) - want) < 0.001, "%s 档开战满血" % String(truck.call("difficulty_name")))
	truck.set("difficulty", 0)
	truck.call("apply_difficulty")

	# ---- 2. 外观与碰撞 ----
	chk(String(truck.call("visual_source")) == "placeholder",
		"模型槽空着 → 用程序化 8×4 自卸低模顶替（实际 %s）" % String(truck.call("visual_source")))
	var box: Vector3 = truck.get("_box_size")
	chk(box == Vector3(3.0, 3.8, 10.6), "碰撞盒 3.0×3.8×10.6 米（实际 %s）" % str(box))
	chk(abs(float(truck.call("box_height")) - 3.8) < 0.001, "盒高 3.8 米（标签挂在 5.0 米）")
	var vis: Node3D = truck.get("_visual")
	var mn: Node3D = truck.get("_model_node")
	chk(mn != null and mn.get_child_count() > 40, "占位低模拼出 %d 个部件" % (mn.get_child_count() if mn != null else 0))
	var pwheels := mn.find_child("Wheels", true, false)
	chk(pwheels != null and pwheels.get_child_count() == 8,
		"四轴八轮（实际 %d 个轮子枢轴）" % (pwheels.get_child_count() if pwheels != null else 0))
	var decals := 0
	for c in mn.get_children():
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh is QuadMesh:
			var mm := mi.material_override as StandardMaterial3D
			if mm != null and mm.albedo_texture != null:
				decals += 1
	chk(decals == 2, "货箱两侧各一张「大运重卡」白字贴（实际 %d）" % decals)
	var fb := _fallback_boss()
	chk(fb != null and String(fb.call("visual_source")) == "placeholder",
		"模型文件缺失时自动回退占位低模（实际 %s）" % (String(fb.call("visual_source")) if fb != null else "null"))
	if fb != null:
		fb.free()
	chk(truck.call("aura_radius") > 5.0 and truck.call("aura_radius") < 8.0,
		"贴身光环半径 %.1f 米" % float(truck.call("aura_radius")))

	# ---- 3. 暂无技能：不飞天、不射星点、不砸地 ----
	var arena: Node = truck.call("arena_node")
	var base_y := float(arena.call("floor_y"))
	player.global_position = Vector3(truck.global_position.x, truck.global_position.y + 1.0, truck.global_position.z + 6.0)
	player._enter_arena()
	chk(bool(truck.call("is_arena_mode")), "重卡进入战斗空间")
	chk(not bool(truck.call("has_skills")), "has_skills() = false")
	chk(int(truck.get("_stars").size()) == 0, "无技能档不创建蓄力星点池")
	chk(truck.get("_marker") == null, "无技能档不创建砸地红圈")
	truck.set("_phase_t", 999.0)      # 若误走技能相位机，这里立刻会进前摇
	for _k in 40:
		truck.call("_update_chase", 0.1)
	chk(int(truck.get("_phase")) == 0, "跑满 4 秒仍停在待机相位（没飞天）")
	chk(abs(float(truck.position.y) - base_y) < 0.01, "全程贴地 %.2f（没升空）" % float(truck.position.y))

	# ---- 4. 缓慢驶近 ----
	var px: Vector3 = truck.global_position + Vector3(0.0, 0.0, 20.0)
	player.global_position = px
	var d0 := Vector2(player.global_position.x - truck.global_position.x,
					  player.global_position.z - truck.global_position.z).length()
	for _k in 30:
		truck.call("_update_chase", 0.1)
	var d1 := Vector2(player.global_position.x - truck.global_position.x,
					  player.global_position.z - truck.global_position.z).length()
	chk(d1 < d0 - 8.0, "3 秒驶近 %.1f → %.1f 米" % [d0, d1])
	var spd := float(truck.call("_update_chase", 0.1))
	chk(spd > 2.0 and spd < 5.0, "驶近速度 %.1f 米/秒（慢于玩家步行 5.0）" % spd)
	for _k in 400:
		truck.call("_update_chase", 0.1)
	var d2 := Vector2(player.global_position.x - truck.global_position.x,
					  player.global_position.z - truck.global_position.z).length()
	chk(d2 > 5.8 and d2 < 6.9, "车头停在距玩家 %.1f 米处（半车长+1，不插进模型）" % d2)
	chk(d2 <= truck.call("aura_radius"), "停车点仍在贴身光环范围内（%.1f ≤ %.1f）" % [d2, float(truck.call("aura_radius"))])

	# ---- 5. 贴身光环：站远了不掉血，贴身上才掉 ----
	player.global_position = truck.global_position + Vector3(0.0, 1.0, 30.0)
	player.set("hp", 100.0)
	player.set("_dmg_carry", 0.0)
	truck.set("_dmg_t", 0.0)
	for _k in 30:
		truck.call("_tick_aura", 0.1)      # 掉血已从 _update_chase 拆到 _tick_aura
	chk(abs(float(player.get("hp")) - 100.0) < 0.001, "远处站桩 3 秒不掉血（%.1f）" % float(player.get("hp")))
	player.global_position = truck.global_position + Vector3(0.0, 1.0, 3.0)
	for _k in 30:
		truck.call("_tick_aura", 0.1)
	chk(float(player.get("hp")) < 100.0, "贴身 3 秒被尾气蹭到 %.1f 血" % (100.0 - float(player.get("hp"))))

	# ---- 6. 掉血与击杀奖励 ----
	truck.call("take_damage", 1999)
	chk(not bool(truck.call("is_dead")), "2000 血差 1 点没死")
	truck.call("take_damage", 1)
	chk(bool(truck.call("is_dead")), "打满 2000 血阵亡")
	chk(int(truck.call("reward_count")) == 2, "普通档掉落 ×%d 车货" % int(truck.call("reward_count")))
	chk(String(truck.call("get_reward_item")) == "dogmilk", "掉落物 = 野生狗奶")
	player._exit_arena()
	await _frames(3)
	chk(not bool(truck.call("is_dead")), "离场后重卡复活可再战")
	truck.set("difficulty", 2)
	truck.call("apply_difficulty")
	chk(abs(float(truck.get("max_hp")) - 3000.0) < 0.001, "复活后噩梦档仍是 3000 血")

	# ---- 7. 老 BOSS 不受影响 ----
	chk(milk != null and abs(float(milk.get("max_hp")) - 1000.0) < 0.001, "狗奶普通档仍 1000 血")
	milk.set("difficulty", 2)
	milk.call("apply_difficulty")
	chk(abs(float(milk.get("max_hp")) - 2400.0) < 0.001, "狗奶噩梦档仍按倍率 2400 血")
	chk(String(milk.call("visual_source")) == "box", "狗奶仍是六面贴图盒")
	chk(bool(milk.call("has_skills")), "狗奶技能照常")

	_done()


func _done() -> void:
	print("== 重卡自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  ! " + f)
	quit(1 if fails.size() > 0 else 0)


func _initialize() -> void:
	print("== 大运自检 ==")
	_run()
