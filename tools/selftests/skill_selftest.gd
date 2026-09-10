extends SceneTree
## 技能自检（数字 1）：剑·劈砍 / 弓·快速射击 / 法杖·火球术。
## 只测技能本身：数值（1.6×攻击+定身 / 满蓄一箭 / 1.8×满蓄且大2倍）、耗蓝与每秒回 2 蓝、
## 各自冷却（10/5/15 秒，切走了也照跳）、冷却期照常普攻与切武器、火球放完的 4 秒硬直
## （不能普攻不能切）、蓝不够放不出来。命中链路进狗奶空间真打一发验证掉血+定身。

var fails: Array[String] = []
const ARROW_SCRIPT: GDScript = preload("res://scripts/arrow.gd")


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


const PROG := "user://skill_selftest.progress"


func _mark(t: String) -> void:
	## 进度落盘：stdout 过管道有缓冲，卡住时看这个文件就知道卡在哪一步
	var f := FileAccess.open(PROG, FileAccess.WRITE)
	if f != null:
		f.store_line(t)
		f.flush()


func _arrows() -> int:
	return (ARROW_SCRIPT._active as Array).size()


func _idle(n: int) -> void:
	for _i in n:
		await process_frame


func _phys(n: int) -> void:
	for _i in n:
		await physics_frame


func _find_root(nm: String) -> Node:
	for c in root.get_children():
		if String(c.name) == nm:
			return c
	return null


func _wait_idle_end(sword: Node, max_s := 6.0) -> void:
	## 等剑收招（真实时间：普砍约 1 秒、劈砍放慢到 0.72 倍更长）
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
		if not bool(sword.call("is_attacking")):
			return
		await physics_frame


func _run() -> void:
	SaveManager.stage_new_game(20260906)
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await _idle(20)
	menu.call("_on_new_game")
	SaveManager.pending_seed = 20260906
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
	var sword: Node = player.get_node("Camera3D/Sword")
	var bow: Node = player.get_node("Camera3D/Bow")
	var staff: Node = player.get_node("Camera3D/Staff")

	_mark("步骤1 剑·劈砍")
	# ---- 1. 剑·劈砍：数值 / 耗蓝 / 冷却 ----
	chk(int(player.call("sword_skill_damage")) == 80, "劈砍伤害 = 50×1.6 = 80（强化后跟涨）")
	chk(int(sword.call("skill_cost")) == 50 and float(sword.call("skill_cooldown")) == 10.0,
		"劈砍：耗蓝 50、冷却 10 秒")
	chk(bool(sword.call("skill_ready")), "开局劈砍就绪（满蓝）")
	var mp0: float = player.get("mp")
	chk(bool(sword.call("cast_skill")), "按 1 放出劈砍")
	chk(absf(float(player.get("mp")) - (mp0 - 50.0)) < 0.001, "耗蓝 50（%d → %d）" % [int(mp0), int(player.get("mp"))])
	chk(absf(float(sword.call("skill_cooldown_left")) - 10.0) < 0.05, "进入 10 秒冷却")
	chk(bool(sword.get("_skill_swing")) and bool(sword.call("is_attacking")), "重斩动作播放中（幅度增益已挂上）")
	chk(bool(player.call("weapon_busy")), "动作期间 C 被拦（weapon_busy）")
	chk(not bool(sword.call("cast_skill")), "冷却中再按 1 没反应")
	chk(absf(float(player.get("mp")) - (mp0 - 50.0)) < 0.001, "冷却中按 1 不扣蓝")
	# 冷却期普攻照常：等收招后普砍一下（不进技能冷却、不影响技能冷却倒数）
	await _wait_idle_end(sword)
	chk(not bool(player.call("weapon_busy")), "收招后 C 恢复可用")
	var skill_cd_before: float = sword.call("skill_cooldown_left")
	sword.call("attack")
	chk(bool(sword.call("is_attacking")), "技能冷却期间普攻照常能砍")
	await _wait_idle_end(sword)
	chk(float(sword.call("skill_cooldown_left")) < skill_cd_before, "普攻不动技能冷却（%.2f → %.2f）"
		% [skill_cd_before, float(sword.call("skill_cooldown_left"))])
	# 切走了冷却也照跳
	player.call("_switch_weapon")     # 剑 → 弓
	await _idle(2)
	var cd_switch: float = sword.call("skill_cooldown_left")
	await _phys(70)                   # 约 1.2 秒
	chk(absf(float(sword.call("skill_cooldown_left")) - (cd_switch - 1.2)) < 0.35,
		"切到弓后剑的技能冷却继续倒数（%.2f → %.2f）" % [cd_switch, float(sword.call("skill_cooldown_left"))])

	_mark("步骤2 弓·快速射击")
	# ---- 2. 弓·快速射击 ----
	chk(int(bow.call("skill_cost")) == 30 and float(bow.call("skill_cooldown")) == 5.0,
		"快速射击：耗蓝 30、冷却 5 秒")
	chk(int(bow.call("skill_damage")) == int(bow.call("damage_at", 1.0)),
		"快速射击伤害 = 满蓄那一档（%d）" % int(bow.call("skill_damage")))
	var arrows0: int = _arrows()
	var mpb: float = player.get("mp")
	bow.call("_set_hold", "x", true)          # 先蓄一半
	await _phys(30)
	chk(bool(bow.call("is_charging")), "正在搭弓蓄力")
	chk(bool(bow.call("cast_skill")), "蓄力途中按 1 → 直接改出快速射击")
	chk(not bool(bow.call("is_charging")), "蓄力被技能取代（不再蓄着）")
	chk(_arrows() == arrows0 + 1, "立刻射出一根箭（不经过蓄力）")
	# 蓄力的半秒里蓝也在回（2 点/秒），所以只要求落在"扣了 30、最多又回了 1 点"的区间
	chk(float(player.get("mp")) > mpb - 30.5 and float(player.get("mp")) < mpb - 28.9, "耗蓝 30（期间回了零头）")
	chk(absf(float(bow.call("skill_cooldown_left")) - 5.0) < 0.05, "进入 5 秒冷却")
	chk(not bool(bow.call("cast_skill")), "冷却中按 1 没反应")

	_mark("步骤3 法杖·火球术")
	# ---- 3. 法杖·火球术 ----
	# 把法杖拖进「副武器」栏换下弓（三把武器只能带两把），身上 = 剑 + 法杖
	chk(bool(inv.call("move_item", ["bag", 0], ["eq", "subweapon"])), "法杖拖进副武器栏（换下弓）")
	await _idle(3)
	player.call("_switch_weapon")     # 换装后手上自动回剑，一次 C 就是法杖
	await _idle(2)
	chk(bool(staff.get("active")), "已切到法杖")
	chk(int(staff.call("skill_cost")) == 70 and float(staff.call("skill_cooldown")) == 15.0,
		"火球术：耗蓝 70、冷却 15 秒")
	chk(int(staff.call("skill_damage")) == int(floor(float(staff.call("power", 140)) * 1.8)),
		"火球伤害 = 满蓄伤害×1.8 = %d" % int(staff.call("skill_damage")))
	var orbs0: int = get_nodes_in_group("staff_orb").size()
	var mps: float = player.get("mp")
	chk(bool(staff.call("cast_skill")), "按 1 丢出火球")
	# 出手是同步的：同一帧就把球抓在手心读参数（别等它飞走/撞地消失）
	var orbs_now: Array = get_nodes_in_group("staff_orb")
	if orbs_now.size() == orbs0 + 1:
		var orb: Node = orbs_now[orbs_now.size() - 1]
		chk(absf(float(orb.get("radius")) - 0.52) < 0.001, "火球半径 = 满蓄球×2（0.52 米）")
		chk(int(orb.get("dmg")) == int(staff.call("skill_damage")), "火球结算伤害与 HUD 同数（%d）" % int(orb.get("dmg")))
		chk(absf(float(orb.get("control_sec"))) < 0.001, "火球不带定身")
		chk((orb.get("orb_color") as Color).r > 0.9 and (orb.get("orb_color") as Color).g > 0.3
			and (orb.get("orb_color") as Color).b < 0.3, "火球是火色（%s）" % str(orb.get("orb_color")))
	else:
		chk(false, "火球未出手，球体参数没得查")
	chk(absf(float(player.get("mp")) - (mps - 70.0)) < 0.001, "耗蓝 70")
	chk(absf(float(staff.call("skill_cooldown_left")) - 15.0) < 0.05, "进入 15 秒冷却")
	chk(absf(float(staff.get("_skill_lock")) - 4.0) < 0.05, "火球放完进入 4 秒攻击硬直")
	staff.set("_swing", 0.0)          # 先把甩杖动画收掉（动画拦 C 是普攻动作的规矩，与硬直无关）
	chk(not bool(player.call("weapon_busy")), "硬直期间 C 不被拦（技能冷却/硬直不锁切换，只有攻击间隔锁）")
	var wp_before: int = int(player.get("_weapon"))
	player.call("_switch_weapon")
	chk(int(player.get("_weapon")) != wp_before, "硬直期间按 C 真能切走")
	player.call("_switch_weapon")     # 切回法杖
	await _idle(2)
	chk(bool(staff.get("active")), "切回法杖")
	staff.call("_set_hold", "x", true)
	chk(not bool(staff.call("is_charging")), "硬直期间 X 起不了手（不能普攻）")
	staff.call("_set_hold", "x", false)
	staff.set("_skill_lock", 0.0)     # 手动跳过硬直
	staff.call("_set_hold", "x", true)
	chk(bool(staff.call("is_charging")), "硬直过了普攻恢复（能蓄力）")
	staff.call("_set_hold", "x", false)
	staff.set("_cooldown", 0.0)       # 上一条普攻的攻击间隔（3 秒）清掉，别拦住后面步骤的切换
	chk(absf(float(staff.call("skill_cooldown_left")) - 15.0) < 0.5, "普攻不动火球冷却（仍在 %.1f 秒）"
		% float(staff.call("skill_cooldown_left")))

	_mark("步骤4 蓝与回复")
	# ---- 4. 蓝不够 → 放不出来；每秒回 2 蓝 ----
	player.set("mp", 10.0)
	player.call("restore_mp", 0.0)    # 触发一次刷新（0 不改值）
	chk(not bool(staff.call("skill_ready")), "蓝不够时技能未就绪")
	var mp_low: float = player.get("mp")
	chk(not bool(staff.call("cast_skill")), "蓝不够按 1 放不出来")
	chk(absf(float(player.get("mp")) - mp_low) < 0.001, "放不出来就不扣蓝")
	player.set("mp", 100.0)
	await _phys(140)                  # 约 2.3 秒
	var gained: float = float(player.get("mp")) - 100.0
	chk(gained > 3.5 and gained < 6.0, "法力每秒回 2 点（2.3 秒回了 %.1f 点）" % gained)

	_mark("步骤5 真打一发")
	# ---- 5. 真打一发：劈砍命中 = 1.6 倍伤害 + 定身 1 秒 ----
	var milk: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "dogmilk":
			milk = b
	player.call("_switch_weapon")     # 法杖 → 剑（身上就这两把）
	await _idle(2)
	player.global_position = Vector3(milk.global_position.x, milk.global_position.y + 1.0,
		milk.global_position.z + 2.5)
	await _idle(2)
	player.call("_try_interact_boss")
	await _idle(10)
	chk(bool(player.call("in_arena")), "已进入野生狗奶空间")
	# 进空间后玩家落在竞技场自己的出生点（离 BOSS 远），挪到剑刃够得着的地方再对准
	var to_boss: Vector3 = milk.global_position - player.global_position
	to_boss.y = 0.0
	player.global_position = milk.global_position - to_boss.normalized() * 2.2 + Vector3(0, 1.0, 0)
	await _idle(2)
	var cam: Camera3D = player.get_node("Camera3D")
	cam.look_at_from_position(cam.global_position, milk.global_position + Vector3(0, 1.2, 0), Vector3.UP)
	await _idle(2)
	sword.set("_skill_cd", 0.0)
	player.set("mp", 200.0)
	var hp0: float = milk.get("hp")
	chk(bool(sword.call("cast_skill")), "对着 BOSS 放劈砍")
	await _wait_idle_end(sword)
	var hp1: float = milk.get("hp")
	chk(absf(hp0 - hp1 - 80.0) < 1.0, "劈砍命中扣 1.6×攻击 = 80 血（%.0f → %.0f）" % [hp0, hp1])
	chk(bool(milk.call("is_stunned")), "劈砍把 BOSS 定身 1 秒")
	var feed_txt := ""
	for item in hud.get("_feed_lines"):
		feed_txt = String((item.get("label") as Label).text)
		break
	chk(feed_txt.contains("剑劈砍") and feed_txt.contains("击中"),
		"播报带技能名（%s）" % feed_txt)
	await _phys(80)
	chk(not bool(milk.call("is_stunned")), "1 秒多后定身解除")
	var wl: Label = hud.get("_weapon_label")
	chk(String(wl.text).contains("劈砍") or String(wl.text).contains("冷却"),
		"状态行带技能段（%s）" % String(wl.text))

	# ---- 6. 剑·突刺（数字 2）：冲刺穿透 + 固定 80 + 流血 ----
	_mark("步骤6 剑·突刺")
	chk(int(sword.call("skill2_cost")) == 60 and float(sword.call("skill2_cooldown")) == 15.0,
		"突刺：耗蓝 60、冷却 15 秒（与劈砍各自独立）")
	# 重新贴近 BOSS 并对准（它待机时会游走），再起手
	var to_boss2: Vector3 = milk.global_position - player.global_position
	to_boss2.y = 0.0
	player.global_position = milk.global_position - to_boss2.normalized() * 3.0 + Vector3(0, 1.0, 0)
	await _idle(2)
	cam.look_at_from_position(cam.global_position, milk.global_position + Vector3(0, 1.2, 0), Vector3.UP)
	await _idle(2)
	sword.set("_skill2_cd", 0.0)
	sword.set("_skill_cd", 9.0)       # 故意留一段劈砍冷却，验证两技能互不干扰
	player.set("mp", 200.0)
	var p_before: Vector3 = player.global_position
	var thp0: float = milk.get("hp")
	chk(bool(sword.get("active")), "手上是剑")
	var ev_dn := InputEventKey.new()
	ev_dn.keycode = KEY_2
	ev_dn.pressed = true
	player._unhandled_input(ev_dn)   # 走真实输入层：按下
	await _idle(2)
	# 容差 0.5 秒：冷却按真实时间跳，窗口模式卡顿时这几帧可能吃掉零点几秒
	chk(absf(float(sword.call("skill2_cooldown_left")) - 15.0) < 0.5, "突刺进入 15 秒冷却")
	chk(absf(float(sword.get("_skill_cd")) - 9.0) < 1.0, "突刺不动劈砍的冷却（互不共享，仍约 %.1f）"
		% float(sword.get("_skill_cd")))
	for _i in 40:
		await physics_frame           # 等冲刺跑完（约 0.2 秒）
		if float(player.get("_thrust_left")) <= 0.0:
			break
	chk(player.global_position.distance_to(p_before) > 3.0,
		"人跟着冲了出去（位移 %.1f 米）" % player.global_position.distance_to(p_before))
	var thp1: float = milk.get("hp")
	chk(absf(thp0 - thp1 - 80.0) < 1.0, "穿透目标固定扣 80 血（%.0f → %.0f）" % [thp0, thp1])
	chk(float(milk.get("_bleed_t")) > 9.0, "上了流血（每秒 %d，持续 10 秒）" % int(round(float(milk.get("_bleed_dps")))))
	await _phys(140)                  # ~2.3 秒：该跳两笔流血
	chk(absf(thp1 - float(milk.get("hp")) - 90.0) < 3.0,
		"流血每秒扣 攻击×0.9=45（2.3 秒掉了 %.0f）" % (thp1 - float(milk.get("hp"))))

	# ---- 7. 弓·锁定箭（数字 2）：按住蓄力、松手放追踪箭 ----
	_mark("步骤7 弓·锁定箭")
	chk(bool(inv.call("move_item", ["bag", 0], ["eq", "subweapon"])), "弓换回副武器栏")
	await _idle(3)
	player.call("_switch_weapon")     # → 弓
	await _idle(2)
	chk(bool(bow.get("active")), "已切到弓")
	chk(int(bow.call("skill2_cost")) == 40 and float(bow.call("skill2_cooldown")) == 12.0,
		"锁定箭：耗蓝 40、冷却 12 秒")
	bow.set("_skill2_cd", 0.0)
	bow.set("_skill_cd", 8.0)         # 留一段快速射击冷却验证互不共享
	bow.set("_cooldown", 0.0)         # 早先那箭的 0.5 秒间隔在收起时冻住了，清掉再起手
	player.set("mp", 200.0)
	var a0: int = _arrows()
	var bev_dn := InputEventKey.new()
	bev_dn.keycode = KEY_2
	bev_dn.pressed = true
	player._unhandled_input(bev_dn)  # 走真实输入层：按下
	await _phys(2)
	chk(bool(bow.call("is_charging")) and bool(bow.get("_charge_skill2")), "按住 2 进入锁定箭蓄力")
	await _phys(60)
	chk(float(bow.call("skill2_cooldown_left")) == 0.0, "蓄力期间冷却还没起算（用户要求：发射了才计）")
	await _phys(70)                   # 蓄满
	var bev_up := InputEventKey.new()
	bev_up.keycode = KEY_2
	bev_up.pressed = false
	player._unhandled_input(bev_up)  # 走真实输入层：松手（此前松开事件进不了输入闸，射不出去）
	await _idle(2)
	await _idle(2)
	chk(_arrows() == a0 + 1, "松手放出一支箭")
	if _arrows() == a0 + 1:
		var ar: Node = ARROW_SCRIPT._active[ARROW_SCRIPT._active.size() - 1]
		chk(bool(ar.get("homing")), "这支箭是追踪箭")
		chk(int(ar.get("dmg")) == int(bow.call("skill2_damage", 1.0)), "追踪箭伤害 = 1.5×满蓄（%d）" % int(ar.get("dmg")))
	var cd2: float = float(bow.call("skill2_cooldown_left"))
	chk(absf(cd2 - 12.0) < 0.3, "发射那一刻才进入 12 秒冷却，蓄力花的时间不算（剩 %.1f 秒）" % cd2)
	chk(float(bow.get("_skill_cd")) < 8.0, "锁定箭不动快速射击的冷却（仍在倒数 %.1f）"
		% float(bow.get("_skill_cd")))
	chk(float(player.get("mp")) < 200.0 and float(player.get("mp")) > 150.0,
		"耗蓝 40（期间回了零头，现 %d）" % int(player.get("mp")))

	# ---- 8. 法杖·冰冻术（数字 2）：三颗冰球 + 可叠控 ----
	_mark("步骤8 法杖·冰冻术")
	chk(bool(inv.call("move_item", ["bag", 0], ["eq", "subweapon"])), "法杖再换上")
	await _idle(3)
	player.call("_switch_weapon")
	await _idle(2)
	chk(bool(staff.get("active")), "已切到法杖")
	chk(int(staff.call("skill2_cost")) == 80 and float(staff.call("skill2_cooldown")) == 20.0,
		"冰冻术：耗蓝 80、冷却 20 秒")
	staff.set("_skill2_cd", 0.0)
	staff.set("_skill_cd", 5.0)       # 火球冷却故意留着：两技能互不共享
	player.set("mp", 200.0)
	var orbs1: int = get_nodes_in_group("staff_orb").size()
	var sev_dn := InputEventKey.new()
	sev_dn.keycode = KEY_2
	sev_dn.pressed = true
	player._unhandled_input(sev_dn)  # 走真实输入层：按下
	await _phys(2)
	chk(bool(staff.call("is_charging")) and bool(staff.get("_charge_skill2")), "按住 2 进入冰冻术蓄力")
	var sev_up := InputEventKey.new()
	sev_up.keycode = KEY_2
	sev_up.pressed = false
	player._unhandled_input(sev_up)  # 走真实输入层：点按松手（未蓄满档）
	var orbs2: Array = get_nodes_in_group("staff_orb")
	chk(orbs2.size() == orbs1 + 3, "一次甩出三颗冰球")
	if orbs2.size() >= orbs1 + 3:
		var ice: Node = orbs2[orbs1]
		chk(bool(ice.get("stack_control")), "冰球定身可叠加")
		chk(int(ice.get("dmg")) == int(staff.call("skill2_damage", false)), "冰球伤害=蓝球点按档（%d）" % int(ice.get("dmg")))
		chk(absf(float(ice.get("control_sec")) - 1.0) < 0.001, "点按档每颗定身 1 秒")
		chk(absf((ice.get("orb_color") as Color).b - 1.0) < 0.01, "冰球是冰色（%s）" % str(ice.get("orb_color")))
	chk(absf(float(staff.call("skill2_cooldown_left")) - 20.0) < 0.1, "进入 20 秒冷却")
	chk(absf(float(staff.get("_skill_cd")) - 5.0) < 0.5, "冰冻术不动火球术的冷却（仍约 %.1f）"
		% float(staff.get("_skill_cd")))
	chk(float(player.get("mp")) < 200.0 and float(player.get("mp")) > 115.0,
		"耗蓝 80（现 %d）" % int(player.get("mp")))
	# 叠控：连中两颗 → 定身时长往上叠（封顶 6 秒）
	milk.call("stun", 0.0)
	milk.call("stun", 1.0, true)
	milk.call("stun", 1.0, true)
	chk(absf(float(milk.get("_stun_t")) - 2.0) < 0.05, "两颗叠出 2 秒定身（%.2f）" % float(milk.get("_stun_t")))
	for _i in 8:
		milk.call("stun", 1.0, true)
	chk(float(milk.get("_stun_t")) <= 6.0, "叠控封顶 6 秒（现 %.2f）" % float(milk.get("_stun_t")))
	_done()



func _done() -> void:
	print("\n== 技能自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
