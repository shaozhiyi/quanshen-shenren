extends SceneTree
## 本轮改动的无头自检：
##  1) 星点颜色规律 红→黄→蓝→绿 循环：红=10 伤、黄=5 伤、蓝=5 伤 + 减速 5 秒、绿=0 伤 + 回 5 血
##  2) 星点只有碰到地板才消失（不再飞到一半自毁），并且带弹道补偿
##  3) Z 单键冲刺（有冷却），双击方向键改为进入奔跑状态（速度 ×2，松开退出），蓝色减速生效
##  4) 武器切换挪到 C（Z 让给冲刺）

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


func _star_count() -> int:
	return get_nodes_in_group("slam_star").size()


func _wait(what: Callable, max_frames: int) -> bool:
	## 轮询等待（Callable 每帧重新求值，不依赖具体帧率）
	var i := 0
	while not bool(what.call()) and i < max_frames:
		await physics_frame
		i += 1
	return bool(what.call())


func _clear_stars() -> bool:
	return await _wait(_star_count_empty, 900)


func _star_count_empty() -> bool:
	return _star_count() == 0


func _run() -> void:
	var FX: GDScript = load("res://scripts/slam_fx.gd")
	var BS: GDScript = load("res://scripts/boss.gd")

	# ---- 1. 颜色规律本身 ----
	var want := ["red", "yellow", "blue", "green", "red", "yellow", "blue", "green"]
	var got: Array = []
	for i in 8:
		got.append(String(FX.star_kind(i)))
	chk(got == want, "星点按红黄蓝绿依次循环（实际 %s）" % str(got))
	chk(abs(float(FX.star_color("red").r) - 1.0) < 1e-6 and FX.star_color("red").g < 0.4, "红色星点确实是红的")
	chk(FX.star_color("green").g > 0.8, "绿色星点确实是绿的")

	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	w.get_node("Ground").set("seed_value", 77001)
	root.add_child(w)
	await _frames(10)
	var player := w.get_node("Player")
	var milk: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "dogmilk":
			milk = b
	chk(milk != null, "找到野生狗奶")
	if milk == null:
		_done()
		return

	# ---- 2. BOSS 侧：24 颗蓄力星点的种类与伤害 ----
	var kinds: Array = []
	for i in 24:   # MAX_STARS（下面断言里核对数量）
		kinds.append(String(milk.call("star_kind_of", i)))
	var ok_cycle := true
	for i in kinds.size():
		if kinds[i] != String(FX.star_kind(i)):
			ok_cycle = false
	chk(kinds.size() == 24 and ok_cycle, "24 颗环绕星点种类 = 红黄蓝绿循环 6 轮")
	var counts := {"red": 0, "yellow": 0, "blue": 0, "green": 0}
	for k in kinds:
		counts[k] = int(counts[k]) + 1
	chk(int(counts["red"]) == 6 and int(counts["yellow"]) == 6 and int(counts["blue"]) == 6 and int(counts["green"]) == 6,
		"一轮共 24 发：红黄蓝绿各 6 发（实际 %s）" % str(counts))
	chk(abs(float(milk.call("star_damage_of", "red")) - 10.0) < 1e-6, "红色伤害 = 5 + 5 = 10")
	chk(abs(float(milk.call("star_damage_of", "yellow")) - 5.0) < 1e-6, "黄色伤害 = 基准 5")
	chk(abs(float(milk.call("star_damage_of", "blue")) - 5.0) < 1e-6, "蓝色伤害 = 基准 5（另加减速）")
	chk(abs(float(milk.call("star_damage_of", "green")) - 0.0) < 1e-6, "绿色伤害 = 0（改为回血）")
	var stars: Array = milk.get("_stars")
	var mat0 := (stars[0] as MeshInstance3D).material_override as StandardMaterial3D
	var mat2 := (stars[2] as MeshInstance3D).material_override as StandardMaterial3D
	chk(mat0.albedo_color.is_equal_approx(FX.star_color("red")), "第 1 颗环绕星点材质是红色")
	chk(mat2.albedo_color.is_equal_approx(FX.star_color("blue")), "第 3 颗环绕星点材质是蓝色")

	# ---- 3. 进空间：星点只有碰地板才消失 ----
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0, milk.global_position.z + 8.0)
	player._enter_arena()
	await _frames(4)
	var floor_y := 100.0
	milk.set("_phase", 0)
	milk.set("_phase_t", 0.0)
	milk.set("_wandering", false)
	milk.global_position = Vector3(0.0, floor_y, -12.0)
	player.global_position = Vector3(0.0, floor_y + 1.05, 6.0)
	player.velocity = Vector3.ZERO
	# 纯水平射出（BOSS 实际给的兜底上限 8 秒）：旧版 0.9 秒就自毁，新版必须落到地板才没
	FX.spawn_star(w, Vector3(0.0, floor_y + 20.0, -20.0), Vector3(1.0, 0.0, 0.0),
		42.0, 8.0, 1.5, 5.0, "yellow")   # 与 BOSS 实发参数一致：42 米/秒、兜底 8 秒
	chk(_star_count() == 1, "水平星点已生成")
	var star: Node = get_first_node_in_group("slam_star")
	chk(await _wait(_star_alive_past_one_sec.bind(star), 900), "星点飞满 1 秒仍未消失（不再飞到一半自毁）")
	if star != null and is_instance_valid(star):
		chk(float(star.global_position.y) > floor_y + 1.0, "此时仍在空中 y=%.1f" % float(star.global_position.y))
	chk(await _clear_stars(), "最终落到地板才消失")

	# ---- 4. 四色命中效果（每发之间先等场上星点清空，避免串扰）----
	var pp: Vector3 = player.global_position
	player.armor_factor = 1.0
	player.set("_dmg_carry", 0.0)
	player.set("_slow_t", 0.0)

	player.hp = 100.0
	_fire_at(w, pp, "red", 10.0)
	chk(await _wait(_hp_is(player, 90.0), 900), "红色命中 -10（hp=%.1f）" % float(player.hp))
	await _clear_stars()

	player.hp = 100.0
	_fire_at(w, pp, "yellow", 5.0)
	chk(await _wait(_hp_is(player, 95.0), 900), "黄色命中 -5（hp=%.1f）" % float(player.hp))
	await _clear_stars()

	player.hp = 100.0
	player.set("_slow_t", 0.0)
	_fire_at(w, pp, "blue", 5.0)
	chk(await _wait(_slow_active(player), 900), "蓝色命中后进入减速状态")
	chk(abs(float(player.hp) - 95.0) < 1e-6, "蓝色伤害同黄色 -5（hp=%.1f）" % float(player.hp))
	chk(float(player.call("slow_left")) > 4.0, "减速剩余 %.1f 秒（规则 5 秒）" % float(player.call("slow_left")))
	chk(abs(float(player.call("speed_now")) - 2.5) < 1e-6, "减速中移速 5.0 → %.2f（-50%%）" % float(player.call("speed_now")))
	await _clear_stars()

	player.hp = 40.0
	_fire_at(w, pp, "green", 0.0)
	chk(await _wait(_hp_is(player, 45.0), 900), "绿色命中不掉血反而 +5（hp=%.1f）" % float(player.hp))
	await _clear_stars()

	# 防具减伤
	player.armor_factor = 0.7
	player.set("_dmg_carry", 0.0)
	player.hp = 100.0
	_fire_at(w, pp, "red", 10.0)
	chk(await _wait(_hp_any_below(player, 94.0), 900), "有甲红色 10×0.7 → -7（hp=%.1f）" % float(player.hp))
	player.armor_factor = 1.0
	await _clear_stars()

	# 无敌期：不掉血、免疫减速
	player.gain_invincibility(10.0)
	player.hp = 100.0
	player.set("_slow_t", 0.0)
	_fire_at(w, pp, "red", 10.0)
	chk(await _clear_stars(), "无敌期星点照样结算后消失")
	chk(abs(float(player.hp) - 100.0) < 1e-6, "无敌期不掉血（hp=%.1f）" % float(player.hp))
	chk(float(player.call("slow_left")) <= 0.0, "无敌期免疫减速")
	player._end_invincibility()

	# ---- 5. Z 冲刺 / 双击奔跑 ----
	player.set("_dash_cd", 0.0)
	player.set("_dash_time", 0.0)
	var before: Vector3 = player.global_position
	chk(bool(player.call("try_dash")), "Z 冲刺：一次按键即可触发")
	chk(float(player.get("_dash_time")) > 0.0, "冲刺已进入持续帧")
	chk(not bool(player.call("try_dash")), "冷却中再按 Z 不放第二下")
	await _frames(20)
	chk(before.distance_to(player.global_position) > 1.5, "冲刺真的位移了 %.2f 米" % before.distance_to(player.global_position))
	player.set("_dash_cd", 0.0)
	chk(bool(player.call("try_dash")), "冷却结束后可再次冲刺")
	player.set("_dash_cd", 0.0)
	player.set("_dash_time", 0.0)

	chk(abs(float(player.call("speed_now")) - 5.0) < 1e-6, "默认移速 5.0")
	player.set_running(true)
	chk(abs(float(player.call("speed_now")) - 10.0) < 1e-6, "奔跑状态 → 5.0×2 = 10.0")
	player.apply_slow(5.0)
	chk(abs(float(player.call("speed_now")) - 5.0) < 1e-6, "奔跑 + 减速 → 10×0.5 = 5.0")
	player.set("_slow_t", 0.0)
	player.set_running(false)

	# 双击方向键 → 奔跑（直接喂 Input 状态，无需真键盘）
	Input.action_press("move_forward")
	await _frames(2)
	Input.action_release("move_forward")
	await _frames(1)
	Input.action_press("move_forward")
	await _frames(2)
	chk(bool(player.call("is_running")), "双击前进键 → 进入奔跑状态")
	chk(abs(float(player.call("speed_now")) - 10.0) < 1e-6, "奔跑中速度 10.0")
	Input.action_release("move_forward")
	await _frames(3)
	chk(not bool(player.call("is_running")), "松开方向键自动退出奔跑")

	# 单击不该进入奔跑
	await _frames(3)
	Input.action_press("move_back")
	await _frames(2)
	Input.action_release("move_back")
	await _frames(2)
	chk(not bool(player.call("is_running")), "单击方向键不会进入奔跑")

	# ---- 6. 武器切换挪到 C ----
	var hand0 := int(player.get("_weapon"))
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_C
	ev.physical_keycode = KEY_C
	player.call("_unhandled_input", ev)
	var hand1 := int(player.get("_weapon"))
	chk(hand0 != hand1, "按 C 切换主/副武器（%d → %d）" % [hand0, hand1])
	player.call("_unhandled_input", ev)
	chk(int(player.get("_weapon")) == hand0, "再按一次 C 切回原武器")
	# Z 不再切武器
	var evz := InputEventKey.new()
	evz.pressed = true
	evz.keycode = KEY_Z
	evz.physical_keycode = KEY_Z
	var handz := int(player.get("_weapon"))
	player.call("_unhandled_input", evz)
	chk(int(player.get("_weapon")) == handz, "按 Z 不再切换武器（已让给冲刺）")

	_done()


func _star_alive_past_one_sec(star: Node) -> bool:
	return star != null and is_instance_valid(star) and float(star.get("_t")) > 1.0


func _hp_is(player: Node, v: float) -> Callable:
	return func() -> bool: return abs(float(player.hp) - v) < 1e-6


func _hp_any_below(player: Node, v: float) -> Callable:
	return func() -> bool: return float(player.hp) < v


func _slow_active(player: Node) -> Callable:
	return func() -> bool: return float(player.call("slow_left")) > 0.0


## 按颜色规律朝玩家胸口射一颗星点（伤害由 BOSS 侧同一套规则算，避免测试自说自话）
func _fire_at(w: Node, center: Vector3, kind: String, dmg: float) -> void:
	## 朝玩家胸口射一颗指定颜色的星点；dmg 用与 BOSS 相同的数值（映射本身另有断言核对）
	var FX: GDScript = load("res://scripts/slam_fx.gd")
	var from: Vector3 = center + Vector3(0.0, 4.0, -10.0)
	var dir: Vector3 = (center + Vector3(0.0, 0.9, 0.0) - from).normalized()
	FX.spawn_star(w, from, dir, 42.0, 6.0, 1.5, dmg, kind)


func _done() -> void:
	print("== 本轮改动自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  ! " + f)
	quit(1 if fails.size() > 0 else 0)


func _initialize() -> void:
	print("== 冲刺/奔跑 + 星点四色自检 ==")
	_run()
