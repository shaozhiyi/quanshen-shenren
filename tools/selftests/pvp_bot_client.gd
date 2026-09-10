extends SceneTree
## PVP 自检的机器人（玩家2）：连上房主、报名、等开局、进竞技场后自核权威与掉血，
## 过程写进 pvp_bot.progress 给房主进程看。跑法（由 pvp_selftest 拉起）：
##   godot --headless --path 项目 --script pvp_bot_client.gd

const MARK := "user://pvp_bot.progress"

var _log: Array = []


func _mark(t: String) -> void:
	_log.append(t)
	var f := FileAccess.open(MARK, FileAccess.WRITE)
	if f != null:
		f.store_line("\n".join(_log))
		f.flush()


func _idle(n: int) -> void:
	for _i in n:
		await physics_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	_mark("bot: 启动")
	var lobby: Control = (load("res://scenes/pvp_lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _idle(10)
	lobby.join_ip("127.0.0.1", 7777)
	var last_status := -1
	var last_text := ""
	for i in 300:
		await physics_frame
		var peer = root.get_multiplayer().multiplayer_peer
		if peer != null and peer.get_connection_status() == 2:   # CONNECTION_CONNECTED
			break
	_mark("NET:%d" % (root.get_multiplayer().multiplayer_peer.get_connection_status() if root.get_multiplayer().multiplayer_peer != null else -1))
	for i in 1500:
		if i % 30 == 0:
			var peer = root.get_multiplayer().multiplayer_peer
			var st: int = peer.get_connection_status() if peer != null else -1
			var txt: String = String(lobby.get("_player_list").text).split("|")[0]
			if st != last_status or txt != last_text:
				last_status = st
				last_text = txt
				_mark("t=%ds net=%d players=%d list=[%s]" % [i / 60, st, PvpState.players.size(), txt])
		await physics_frame
		if PvpState.players.size() >= 2:
			_mark("LOBBY_OK")
			break
	_mark("JOINED:%d" % PvpState.players.size())
	if PvpState.players.size() < 2:
		quit(1)
		return
	# 等房主点开始并切进竞技场
	for i in 2400:
		await physics_frame
		if PvpState.started and current_scene != null and String(current_scene.name) == "PvpArena":
			break
	var in_arena: bool = current_scene != null and String(current_scene.name) == "PvpArena"
	_mark("ARENA:%s" % in_arena)
	if not in_arena:
		quit(1)
		return
	await _idle(30)
	# 本机那名玩家：authority 是自己（机器人=peer 2），且不是房主节点
	var players_root: Node = current_scene.get_node("Players")
	var mine: Node = null
	for n in players_root.get_children():
		if n.is_multiplayer_authority():
			mine = n
	if mine == null:
		_mark("NO_AUTHORITY")
		quit(1)
		return
	_mark("AUTH:%d hp=%d" % [int(mine.pvp_id), int(mine.hp)])
	# 等房主打我一拳（700→600），确认房主结算能广播到我这里
	for i in 600:
		await physics_frame
		if float(mine.hp) < float(mine.max_hp):
			break
	_mark("HP:%d" % int(mine.hp))
	if absf(float(mine.hp) - 600.0) < 1.0:
		_mark("OK")
	else:
		_mark("BAD_HP")
		quit(1)
		return
	# 机器人主动上报一笔伤害（any_peer 链路）：打房主，房主应结算成 600
	var other: Node = null
	for n in players_root.get_children():
		if not n.is_multiplayer_authority():
			other = n
	if other != null:
		other.take_damage(100, "测试")
		for i in 600:
			await physics_frame
			if float(other.hp) <= 600.0:
				break
		_mark("CLAIM:%d" % int(other.hp))
	else:
		_mark("NO_OTHER")
		quit(1)
		return
	# ---- 武器/动作同步：核对房主身上的手+默认剑，自己换弓放一箭，再等房主那一剑 ----
	var ok_hand: bool = other.get("_hand") != null
	var rp: Dictionary = other.get("_hand_parts")
	var ok_sword: bool = rp.has("sword") and (rp["sword"] as Node3D).visible
	_mark("RH:%s,%s" % [ok_hand, ok_sword])
	mine._switch_weapon()              # 剑 → 弓（房主那边应看到他亮弓）
	await _idle(10)
	mine._bow.call("_set_hold", "lmb", true)
	await _idle(20)
	mine._bow.call("_set_hold", "lmb", false)   # 放箭（ACT_SHOOT 广播）
	_mark("SW:%d" % int(mine.get("_net_weapon")))
	var saw_slash := false
	for i in 900:
		await physics_frame
		if int(other.get("_rem_act")) == 1:
			saw_slash = true
			break
	_mark("ACT:%s" % saw_slash)
	# 等房主结算一次定身→减速：速度应减半（5.0 → 2.5）
	for i in 300:
		await physics_frame
		if float(mine.get("_slow_t")) > 0.0:
			break
	var slow_on: bool = float(mine.get("_slow_t")) > 0.0
	var spd: float = float(mine.call("speed_now"))
	_mark("SLOW:%s slow=%.1f speed=%.1f" % [slow_on, float(mine.get("_slow_t")), spd])
	# 单独写一份最终结论文件（只写一次、写完即退，房主等本进程退出后读）
	var f2 := FileAccess.open("user://pvp_bot_slow.progress", FileAccess.WRITE)
	if f2 != null:
		f2.store_line("SLOW:%s slow=%.1f speed=%.1f" % [slow_on, float(mine.get("_slow_t")), spd])
		f2.flush()
	quit(0 if (slow_on and absf(spd - 2.5) < 0.01) else 1)
