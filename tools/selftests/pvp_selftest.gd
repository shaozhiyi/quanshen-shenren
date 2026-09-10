extends SceneTree
## PVP 联机自检（双进程）：本进程当房主（创建房间 7777 / 空白地图），
## 拉一个子 Godot 进程跑 pvp_bot_client.gd 当玩家2，走真实的大厅→开始→竞技场链路。
## 验证：ENet 建房/加入、大厅名单广播、开局切场景、竞技场双玩家、房主结算→远端掉血、
## 机器人上报→房主掉血（双向结算）。

const PROG := "user://pvp_selftest.progress"
const BOT := "res://tools/selftests/pvp_bot_client.gd"
const ROOM := 7777

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)
	_mark("FAIL: " + msg)


func _mark(t: String) -> void:
	var f := FileAccess.open(PROG, FileAccess.WRITE)
	if f != null:
		f.store_line(t)
		f.flush()


func _bot_mark() -> String:
	var f := FileAccess.open("user://pvp_bot.progress", FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _idle(n: int) -> void:
	for _i in n:
		await physics_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	_mark("host: 进大厅")
	var lobby: Control = (load("res://scenes/pvp_lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _idle(10)
	lobby.get("_room_edit").text = "7777"
	lobby.get("_map_opt").selected = 1        # 空白
	lobby._on_create()
	await _idle(10)
	chk(root.get_multiplayer().is_server(), "房主 ENet 服务器已开（端口 %d）" % 24565)
	chk(String(PvpState.room_code) == "7777", "房间号 7777")

	# ---- 拉起机器人（玩家2）----
	_mark("host: 启动机器人")
	var godot_exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var bot_out := ProjectSettings.globalize_path("user://pvp_bot_out.txt")   # 给 cmd 重定向用，必须是真实路径
	var bot_pid := OS.create_process("cmd.exe", ["/C", '"%s" --headless --path "%s" --script "%s" > "%s" 2>&1'
		% [godot_exe, proj, BOT, bot_out]])
	chk(bot_pid > 0, "机器人子进程已启动（pid %d）" % bot_pid)
	for i in 1200:
		await physics_frame
		if PvpState.players.size() >= 2:
			break
	chk(PvpState.players.size() == 2, "玩家2 已报名进房（%d/4）" % PvpState.players.size())
	if PvpState.players.size() < 2:
		_done()
		return
	for i in 600:
		await physics_frame
		if _bot_mark().contains("LOBBY_OK"):
			break
	chk(_bot_mark().contains("LOBBY_OK"), "玩家2 的名单广播已确认（心跳兜底生效）")
	chk(String(PvpState.name_of(2)) == "玩家2", "成员名字由房主分配（%s）" % PvpState.name_of(2))

	# ---- 房主点开始 ----
	_mark("host: 点开始")
	lobby._on_start()
	await _idle(5)
	chk(bool(PvpState.started), "房主开始，锁门")
	for i in 1800:
		await physics_frame
		if current_scene != null and String(current_scene.name) == "PvpArena":
			break
	chk(current_scene != null and String(current_scene.name) == "PvpArena", "房主已切进竞技场")
	await _idle(30)
	var players_root: Node = current_scene.get_node("Players")
	chk(players_root.get_child_count() == 2, "竞技场里两名玩家都已生成")
	var me: Node = null
	var foe: Node = null
	for n in players_root.get_children():
		if n.is_multiplayer_authority():
			me = n
		else:
			foe = n
	chk(me != null and foe != null, "本机玩家与远程玩家各就各位")
	chk(int(me.max_hp) == 700, "PVP 每人 700 血（单机是 100）")

	# ---- 房主结算 → 机器人掉血 ----
	_mark("host: 打机器人一拳")
	current_scene.settle_hit(int(foe.pvp_id), 100, "测试拳头", 1)
	for i in 600:
		await physics_frame
		if _bot_mark().contains("HP:600"):
			break
	chk(_bot_mark().contains("HP:600"), "机器人收到房主结算（700→600）")

	# ---- 机器人打房主 → 房主掉血（any_peer 上报链路，由机器人真发）----
	var my_hp0: float = float(me.hp)
	for i in 600:
		await physics_frame
		if _bot_mark().contains("CLAIM:"):
			break
	chk(_bot_mark().contains("CLAIM:600"), "机器人上报的伤害也由房主结算（%d → %d）" % [int(my_hp0), int(me.hp)])

	# ---- 武器/动作同步：房主挥一剑（机器人应看到），机器人换弓放箭（房主应看到）----
	var foe_parts: Dictionary = foe.get("_hand_parts")
	chk(foe.get("_hand") != null and foe_parts.has("sword"), "机器人身上有武器挂点与三把武器外观")
	me._sword.call("attack")
	for i in 900:
		await physics_frame
		if foe_parts.has("bow") and (foe_parts["bow"] as Node3D).visible:
			break
	chk(foe_parts.has("bow") and (foe_parts["bow"] as Node3D).visible, "机器人换弓后房主看到他亮出弓")
	for i in 900:
		await physics_frame
		if int(foe.get("_rem_act")) == 5:
			break
	chk(int(foe.get("_rem_act")) == 5, "机器人放箭的动作同步到房主（ACT_SHOOT）")
	# 机器人那支箭应在房主机器上留下"复制体"（纯外观，不参与伤害结算）
	var reps := 0
	for c in current_scene.get_children():
		if String(c.name) == "Replica":
			reps += 1
	chk(reps > 0, "机器人射出的箭在房主机器上有复制体（%d 个）" % reps)
	# ---- 劈砍命中=减速50%：房主结算定身（现在是减速），机器人速度应减半 ----
	current_scene.settle_stun(int(foe.pvp_id), 2.0)
	# 等机器人进程退出再读它的最终结论文件（边写边读会读到半截字符串）
	for i in 600:
		await physics_frame
		if bot_pid > 0 and not OS.is_process_running(bot_pid):
			break
	var slow_txt := ""
	var slow_file := "user://pvp_bot_slow.progress"
	var fs := FileAccess.open(slow_file, FileAccess.READ)
	if fs != null:
		slow_txt = fs.get_as_text()
	chk(slow_txt.contains("SLOW:true") and slow_txt.contains("speed=2.5"),
		"被劈砍命中=减速50%%（机器人：%s）" % slow_txt)

	# ---- 等机器人的 OK 标记（它自己核完竞技场与血量）----
	for i in 900:
		await physics_frame
		if _bot_mark().contains("ACT:") or _bot_mark().contains("SLOW:"):
			break
	chk(_bot_mark().contains("RH:true,true"), "房主在机器人身上也挂好了武器手（默认亮剑）")
	chk(_bot_mark().contains("ACT:true"), "房主挥的那一剑同步到了机器人")
	for i in 900:
		await physics_frame
		if _bot_mark().contains("OK"):
			break
	chk(_bot_mark().contains("OK"), "机器人自检通过（进图/权威/掉血全部确认）")
	_done()


func _done() -> void:
	print("\n== PVP 联机自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	_mark("DONE fails=%d" % fails.size())
	quit(0 if fails.is_empty() else 1)
