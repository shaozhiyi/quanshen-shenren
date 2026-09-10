extends SceneTree
## 第三武器·法杖自检：走真实开局链路（菜单 → 分帧进场景），然后核对
## 背包初始放杖、装备栏只有两格武器位（三把只能带两把）、C 在已装备之间循环、
## 点按/蓄力两档数值、红蓝效果、蓝球"只定身不打断"、2 秒冷却（冷却期也不许切）、
## 强化（HUD 红蓝数字都要跟着涨）、播报、存档往返与老存档补发。

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
	var inv: Node = hud.get_node("Inventory")
	var staff: Node = w.get_node("Player/Camera3D/Staff")
	var bow: Node = w.get_node("Player/Camera3D/Bow")
	var sword: Node = w.get_node("Player/Camera3D/Sword")

	# ---- 1. 初始状态：杖在背包第一格、装备栏只有武器/副武器两格 ----
	chk(staff != null, "Player/Camera3D/Staff 已挂进场景")
	chk(String(inv.call("bag_get", 0)) == "staff", "法杖初始在背包第一格")
	chk(String(inv.call("eq_get", "weapon")) == "sword", "开局「武器」栏是剑")
	chk(String(inv.call("eq_get", "subweapon")) == "bow", "开局「副武器」栏是弓")
	chk(String(inv.call("eq_get", "staff")) == "", "已经没有「法杖」这一格（问它也不报错）")
	chk(not bool(staff.get("active")), "未装备时法杖不显示")
	chk(not bool(bow.get("active")) and bool(sword.get("active")), "开局手上还是剑")
	chk(int(player.call("equipped_count")) == 2, "身上两把武器（%d）" % int(player.call("equipped_count")))

	# ---- 2. 三把武器抢两格：拖法杖进武器栏＝换下剑，剑回背包 ----
	chk(not bool(inv.call("move_item", ["bag", 0], ["eq", "armor"])), "法杖塞不进防具栏")
	chk(bool(inv.call("move_item", ["bag", 0], ["eq", "weapon"])), "把法杖拖进「武器」栏")
	chk(String(inv.call("eq_get", "weapon")) == "staff" and String(inv.call("bag_get", 0)) == "sword",
		"法杖换下剑、剑回到那一格（换装不是加格）")
	chk(int(inv.call("count_of", "staff")) == 1 and int(inv.call("count_of", "sword")) == 1,
		"来回搬没复制出第二根杖/第二把剑")
	chk(int(player.call("equipped_count")) == 2, "身上还是两把：%d" % int(player.call("equipped_count")))
	chk(bool(bow.get("active")) and not bool(sword.get("active")) and not bool(staff.get("active")),
		"手上的剑被换下 → 自动拿还在身上的弓")
	player.call("_switch_weapon")
	chk(int(player.get("_weapon")) == 2 and bool(staff.get("active")) and not bool(bow.get("active")),
		"C → 法杖（在两把已装备之间切）")
	player.call("_switch_weapon")
	chk(int(player.get("_weapon")) == 1 and bool(bow.get("active")), "再按 C → 回弓（两把循环）")
	# 法杖同样能落「副武器」栏：把弓换下去
	chk(bool(inv.call("move_item", ["eq", "weapon"], ["eq", "subweapon"])), "武器栏与副武器栏可以互换")
	chk(String(inv.call("eq_get", "weapon")) == "bow" and String(inv.call("eq_get", "subweapon")) == "staff",
		"现在副武器栏是法杖、武器栏是弓")
	chk(int(player.call("equipped_count")) == 2, "换格子不会多出一把（身上仍两把）")
	# 摆回后面要用的样子：武器栏法杖、副武器栏弓、剑留背包
	inv.call("move_item", ["eq", "subweapon"], ["eq", "weapon"])
	player.call("_switch_weapon")
	chk(int(player.get("_weapon")) == 2 and bool(staff.get("active")), "切回法杖，后面都拿它打")

	# ---- 3. 四档数值：红/蓝 × 点按/蓄满 ----
	staff.set_process(false)                 # 下面手动推 _process，帧率不影响断言
	var plans := []
	for combo in [[false, false], [false, true], [true, false], [true, true]]:
		staff.set("_next_blue", combo[0])
		staff.set("_charging", true)
		staff.set("_charge", 4.0 if combo[1] else 0.4)
		plans.append(staff.call("shot_plan"))
	staff.set("_charging", false)
	staff.set("_charge", 0.0)
	chk(int(plans[0].damage) == 80 and float(plans[0].control) == 0.0, "红·点按 = 80 伤、无控制")
	chk(int(plans[1].damage) == 140 and float(plans[1].control) == 0.0, "红·蓄满 = 140 伤")
	chk(int(plans[2].damage) == 50 and absf(float(plans[2].control) - 1.0) < 1e-6, "蓝·点按 = 50 伤 + 定身 1 秒")
	chk(int(plans[3].damage) == 90 and absf(float(plans[3].control) - 1.5) < 1e-6, "蓝·蓄满 = 90 伤 + 定身 1.5 秒")
	chk(float(plans[3].radius) > float(plans[0].radius) * 1.5,
		"蓄满球明显更大（%.2f vs %.2f 米）" % [float(plans[3].radius), float(plans[0].radius)])
	chk(plans[0].color != plans[2].color, "红蓝两色确实不同")

	# ---- 4. 长按蓄力：3 秒封顶，松手才出手；蓄力期间 C 被拦 ----
	staff.set_process(true)
	staff.call("_set_hold", "x", true)
	await _idle(2)
	chk(bool(staff.call("is_charging")), "按住 X 进入蓄力")
	chk(bool(player.call("weapon_busy")), "蓄力中 weapon_busy()=true（C 不让切）")
	for _i in 70:
		staff.call("_process", 0.1)          # 手动推 7 秒
	var over := float(staff.call("charge_ratio"))
	chk(over > 0.99, "蓄力比例封顶在 1.0（%.2f）" % over)
	chk(bool(staff.call("is_fully_charged")), "4 秒后算蓄满")
	# 起手那一刻才会随机定色，所以想测哪一档就得先起手、再把颜色钉死
	staff.set("_next_blue", false)
	var before_shots := get_nodes_in_group("staff_orb").size()
	staff.call("_set_hold", "x", false)      # 松手 → 出手
	await _idle(2)
	chk(get_nodes_in_group("staff_orb").size() == before_shots + 1, "松手射出一颗球")
	chk(not bool(staff.call("is_charging")), "出手后不再蓄力")
	var cd: float = staff.call("cooldown_left")
	chk(cd > 2.5 and cd <= 3.0, "冷却 3 秒开始倒数（剩 %.2f）" % cd)
	chk(bool(player.call("weapon_busy")), "冷却期间也算手上有事 → weapon_busy()=true")
	var w_before: int = int(player.get("_weapon"))
	player.call("_switch_weapon")
	chk(int(player.get("_weapon")) == w_before, "冷却中按 C 切不动（用户要求：冷却期间不能切换武器）")
	staff.call("_set_hold", "x", true)
	chk(not bool(staff.call("is_charging")), "冷却中按 X 不起手（共享同一份冷却）")
	staff.call("_set_hold", "x", false)

	# ---- 5. 真打一发：进空间，红球掉血、蓝球定身且不打断 ----
	var milk: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "dogmilk":
			milk = b
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0,
		milk.global_position.z + 8.0)
	await _idle(2)
	player.call("_try_interact_boss")
	await _idle(10)
	chk(bool(player.call("in_arena")), "已进入野生狗奶空间")
	var cam: Camera3D = player.get_node("Camera3D")
	cam.look_at_from_position(cam.global_position, milk.global_position + Vector3(0, 1.2, 0), Vector3.UP)
	await _idle(2)
	staff.set("active", true)
	staff.set_process(false)
	var hp0: float = milk.get("hp")
	staff.set("_cooldown", 0.0)
	staff.set("_swing", 0.0)                 # _process 关着，甩杖状态要手动清
	staff.call("_set_hold", "x", true)       # 起手（随机定色）
	staff.set("_next_blue", false)           # 再钉成红球
	staff.call("_set_hold", "x", false)
	for _i in 40:
		await physics_frame
	var hp1: float = milk.get("hp")
	chk(absf(hp0 - hp1 - 80.0) < 1.0, "红球命中扣 80 血（%.0f → %.0f）" % [hp0, hp1])
	print("     播报：%s" % str(_feed_texts(hud)))

	# 蓝球：定身但不打断（BOSS 待机时会游走，重新对准再打）
	cam.look_at_from_position(cam.global_position, milk.global_position + Vector3(0, 1.2, 0), Vector3.UP)
	await _idle(2)
	staff.set("_cooldown", 0.0)
	staff.set("_swing", 0.0)
	staff.call("_set_hold", "x", true)
	staff.set("_next_blue", true)            # 钉成蓝球
	staff.call("_set_hold", "x", false)
	for _i in 40:
		await physics_frame
	var hp2: float = milk.get("hp")
	chk(absf(hp1 - hp2 - 50.0) < 1.0, "蓝球命中扣 50 血（%.0f → %.0f）" % [hp1, hp2])
	chk(bool(milk.call("is_stunned")), "蓝球命中后 BOSS 被定身")
	var phase_now: int = milk.get("_phase")
	var pt_now: float = milk.get("_phase_t")
	for _i in 30:
		await physics_frame            # 无头模式 process_frame 跑得飞快，按秒等要用物理帧
	chk(int(milk.get("_phase")) == phase_now, "定身期间相位不变（还是 %d，没被打断）" % phase_now)
	chk(absf(float(milk.get("_phase_t")) - pt_now) < 1e-6, "定身期间相位计时也不推进")
	for _i in 100:
		await physics_frame            # 100 × 1/60 ≈ 1.67 秒 > 定身 1 秒
	chk(not bool(milk.call("is_stunned")), "1 秒多后定身自动解除")
	chk(float(milk.get("_phase_t")) > pt_now, "解除后接着原来的动作继续（%.2f → %.2f）" % [pt_now, float(milk.get("_phase_t"))])
	staff.set_process(true)

	# ---- 6. 强化只认法杖自己（法杖此刻在「武器」栏）----
	inv.call("add_item", "stone", 3)
	for _i in 3:
		inv.call("use_slot", ["eq", "weapon"])
		await _idle(1)
	chk(int(player.call("enhance_level_of", "staff")) == 3, "双击法杖 3 次 → 法杖 +3")
	chk(int(player.call("enhance_level_of", "sword")) == 0, "剑没被牵连（仍 +0）")
	var r0: Array = staff.call("enhanced_range")
	chk(int(r0[0]) == int(floor(80.0 * pow(1.1, 3.0))), "红球点按随强化变 %d" % int(r0[0]))
	var b0: Array = staff.call("blue_enhanced_range")
	chk(int(b0[0]) == int(floor(50.0 * pow(1.1, 3.0))) and int(b0[1]) == int(floor(90.0 * pow(1.1, 3.0))),
		"蓝球两档也随强化变 %d/%d" % [int(b0[0]), int(b0[1])])
	# HUD 那行必须报最终值：曾经红球涨了蓝球还写底数（看到的≠打出的）
	player.call("_equip", 2)
	await _idle(3)
	var wl: Label = hud.get("_weapon_label")
	var want := "蓝%d/%d" % [int(b0[0]), int(b0[1])]
	chk(String(wl.text).contains(want), "HUD 法杖行的蓝球数字跟着强化涨（%s）" % String(wl.text))

	# ---- 7. 存档往返 + 老存档补发 ----
	var save: Dictionary = player.call("save_state")
	save.merge(inv.call("save_state"))
	chk(int(save.get("weapon")) == 2, "存档记下手上是法杖（%s）" % str(save.get("weapon")))
	var eqd: Dictionary = save.get("equipment", {})
	chk(String(eqd.get("weapon", "")) == "staff", "存档把法杖记在「武器」栏下（不再有第四格）")
	chk(not eqd.has("staff"), "存档结构里已经没有 staff 这一栏")
	# 走真实读档路径：pending_load → player._apply_loaded_state
	SaveManager.pending_load = save
	player.call("_apply_loaded_state")
	await _idle(2)
	chk(int(player.call("enhance_level_of", "staff")) == 3, "读档后法杖仍 +3")
	# 上一版的存档：法杖记在已经不存在的 equipment.staff 栏里 → 读进来不能凭空丢掉
	var v1_save := {
		"player": {"weapon": 2, "enhance": {"sword": 0, "bow": 0, "armor": 0, "staff": 1}},
		"equipment": {"weapon": "sword", "subweapon": "bow", "armor": "armor", "staff": "staff"},
		"bag": ["", "", "", ""], "bag_counts": [0, 0, 0, 0],
	}
	SaveManager.pending_load = v1_save
	player.call("_apply_loaded_state")
	inv.call("load_state", v1_save)
	await _idle(2)
	chk(int(inv.call("count_of", "staff")) == 1, "上一版「法杖栏」里的杖读进来还在身上/背包（%d 根）"
		% int(inv.call("count_of", "staff")))
	chk(int(player.call("equipped_count")) == 2, "两格装备栏不会被三把武器撑爆")
	# 老存档：完全没有法杖这回事
	var old_save := {
		"player": {"weapon": 1, "enhance": {"sword": 2, "bow": 0, "armor": 0}},
		"equipment": {"weapon": "sword", "subweapon": "bow", "armor": "armor"},
		"bag": ["", "", "", ""], "bag_counts": [0, 0, 0, 0],
	}
	SaveManager.pending_load = old_save
	player.call("_apply_loaded_state")
	inv.call("load_state", old_save)
	await _idle(2)
	chk(int(player.call("enhance_level_of", "sword")) == 2, "老存档的剑 +2 照常还原")
	chk(int(player.call("enhance_level_of", "staff")) == 0, "老存档没记法杖 → 法杖回 +0（不清零会白送等级）")
	chk(String(inv.call("bag_get", 0)) == "staff" and int(inv.call("count_of", "staff")) == 1,
		"老存档读进来会补发一根法杖到背包（%d 根）" % int(inv.call("count_of", "staff")))
	chk(String(inv.call("eq_get", "weapon")) == "sword" and String(inv.call("eq_get", "subweapon")) == "bow",
		"补发的法杖不挤占已有的两把（还是剑+弓）")
	_done()


func _feed_texts(hud: Node) -> Array[String]:
	var out: Array[String] = []
	for item in hud.get("_feed_lines"):
		out.append(String((item.get("label") as Label).text))
	return out


func _done() -> void:
	print("\n== 法杖自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
