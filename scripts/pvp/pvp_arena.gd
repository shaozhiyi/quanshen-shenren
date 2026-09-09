extends Node3D
## PVP 竞技场：按大厅名单生成玩家、建房主结算的伤害/流血/定身账本、计分与重生。
## 结算规则：谁的武器打中了谁，只在"射手那台机器"发生（弹体只在他那儿存在），
## 他把命中报给房主；房主记账后把血量广播给所有人——生杀大权只在房主手里。
const PLAYER_SCRIPT := preload("res://scripts/pvp/pvp_player.gd")
const HUD_SCRIPT := preload("res://scripts/pvp/pvp_hud.gd")
const MAPS_SCRIPT := preload("res://scripts/pvp/pvp_maps.gd")
const REPLICA_SCRIPT := preload("res://scripts/pvp/pvp_replica.gd")
const MENU_SCENE := "res://scenes/menu.tscn"
var players_root: Node3D
var hud: CanvasLayer
var local_player: Node
# ---- 房主账本 ----
var hp := {}                # id -> 当前血
var kills := {}             # id -> 击杀数
var last_attacker := {}     # id -> 最后打他的人
var inv_until := {}         # id -> 无敌剩余秒（狗奶）
var bleed := {}             # id -> {dps, t, from}
var _claim_last := {}       # sender -> msec（限频：同一人 50ms 内的重复上报只认第一笔）
var _bleed_tick := 0.0
var _over := false
func _ready() -> void:
	if PvpState.players.size() < PvpState.MIN_PLAYERS:
		# 不是从大厅进来的（直接 F6 跑场景）：回主页
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
		return
	var spawns: Array = await PvpMaps.build(PvpState.map_name, self)
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	for i in PvpState.players.size():
		var p: Dictionary = PvpState.players[i]
		var node: CharacterBody3D = PLAYER_SCRIPT.new()
		node.setup(int(p.id), String(p.name), spawns[i % spawns.size()])
		players_root.add_child(node)
		hp[int(p.id)] = PvpState.MAX_HP
		kills[int(p.id)] = 0
		if int(p.id) == multiplayer.get_unique_id():
			local_player = node
	var hud_node := CanvasLayer.new()
	hud_node.name = "HUD"
	hud_node.set_script(HUD_SCRIPT)
	add_child(hud_node)
	hud = hud_node
	hud.call("bind", local_player)
	_update_scoreboard()
	hud.call("announce", "地图 %s ｜ 单打独斗 · 每人 %d 血 ｜ 先到 %d 杀获胜" % [
		PvpState.map_name, int(PvpState.MAX_HP), PvpState.WIN_KILLS])
	multiplayer.server_disconnected.connect(_on_server_lost)
	multiplayer.peer_disconnected.connect(_on_peer_left)
func _player_node(id: int) -> Node:
	return players_root.get_node_or_null("P%d" % id)
func _on_server_lost() -> void:
	multiplayer.multiplayer_peer = null
	PvpState.reset()
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
func _on_peer_left(id: int) -> void:
	# 有人掉线：房主把他标记出局（不再重生），画面上直接消失
	if not multiplayer.is_server():
		return
	var n := _player_node(id)
	if n != null:
		n.call("set_dead", true)
	hud.call("announce", "%s 掉线退出了" % PvpState.name_of(id))
# ---- 命中上报（射手所在机器 → 房主）----
@rpc("any_peer", "call_remote", "reliable")
func rpc_claim_hit(victim_id: int, dmg: int, weapon: String) -> void:
	if multiplayer.is_server():
		settle_hit(victim_id, dmg, weapon, multiplayer.get_remote_sender_id())
@rpc("any_peer", "call_remote", "reliable")
func rpc_claim_bleed(victim_id: int, attacker_id: int, dps: float, seconds: float) -> void:
	if multiplayer.is_server():
		settle_bleed(victim_id, attacker_id, dps, seconds)
@rpc("any_peer", "call_remote", "reliable")
func rpc_claim_stun(victim_id: int, sec: float) -> void:
	if multiplayer.is_server():
		settle_stun(victim_id, sec)
@rpc("any_peer", "call_remote", "reliable")
func rpc_notify_invincible(peer_id: int, dur: float) -> void:
	if multiplayer.is_server():
		notify_invincible(peer_id, dur)
# ---- 房主结算 ----
func settle_hit(victim_id: int, dmg: int, weapon: String, attacker_id: int) -> void:
	if not multiplayer.is_server() or _over:
		return
	if attacker_id <= 0:
		attacker_id = 1
	var now := Time.get_ticks_msec()
	if now - int(_claim_last.get(attacker_id, 0)) < 40:
		return                       # 同一个人 40ms 内的连报只认第一笔（防刷）
	_claim_last[attacker_id] = now
	dmg = clampi(dmg, 0, 400)
	if dmg <= 0 or victim_id == attacker_id:
		return
	if float(inv_until.get(victim_id, 0.0)) > 0.0:
		return                       # 狗奶无敌中
	if not hp.has(victim_id) or int(hp[victim_id]) <= 0:
		return
	last_attacker[victim_id] = attacker_id
	_apply_damage(victim_id, dmg, weapon, attacker_id)
func _apply_damage(victim_id: int, dmg: int, weapon: String, attacker_id: int) -> void:
	hp[victim_id] = maxf(float(hp[victim_id]) - float(dmg), 0.0)
	_send_apply_hp(victim_id, float(hp[victim_id]), attacker_id, weapon)
	if float(hp[victim_id]) <= 0.0:
		_on_kill(victim_id, attacker_id)
func settle_bleed(victim_id: int, attacker_id: int, dps: float, seconds: float) -> void:
	if not multiplayer.is_server():
		return
	bleed[victim_id] = {"dps": dps, "t": seconds, "from": attacker_id}
func settle_stun(victim_id: int, sec: float) -> void:
	if not multiplayer.is_server():
		return
	# 定身只跟本人有关：定向发给他（他校验发件人是房主）
	rpc_id(victim_id, "rpc_apply_stun", victim_id, clampf(sec, 0.0, 2.0))
func notify_invincible(peer_id: int, dur: float) -> void:
	if multiplayer.is_server():
		inv_until[peer_id] = dur
func _process(delta: float) -> void:
	if not multiplayer.is_server() or _over:
		return
	# 无敌倒计时
	for k in inv_until.keys():
		if float(inv_until[k]) > 0.0:
			inv_until[k] = maxf(float(inv_until[k]) - delta, 0.0)
	# 流血：每秒一跳，直接走房主结算（不打断、不播报单跳）
	if bleed.is_empty():
		return
	_bleed_tick += delta
	if _bleed_tick < 1.0:
		return
	_bleed_tick -= 1.0
	for vid in bleed.keys():
		var b: Dictionary = bleed[vid]
		if float(b.t) <= 0.0 or not hp.has(vid) or float(hp[vid]) <= 0.0:
			continue
		b.t = float(b.t) - 1.0
		last_attacker[vid] = int(b.from)
		_apply_damage(vid, int(round(float(b.dps))), "流血", int(b.from))
	for vid in bleed.keys():
		if float(bleed[vid].t) <= 0.0:
			bleed.erase(vid)
# ---- 定向发送：本环境（两台无头进程互测/局域网实测）里 rpc() 广播不稳定，
# 统一改成按名单逐个 rpc_id + 本地直调，谁都不会漏 ----
func _peers() -> Array:
	var out: Array = []
	for p in PvpState.players:
		var id := int(p.id)
		if id != multiplayer.get_unique_id():
			out.append(id)
	return out
func _send_apply_hp(peer_id: int, value: float, attacker_id: int, weapon: String) -> void:
	for peer in _peers():
		rpc_id(peer, "rpc_apply_hp", peer_id, value, attacker_id, weapon)
	rpc_apply_hp(peer_id, value, attacker_id, weapon)
func _send_died(peer_id: int, killer_id: int) -> void:
	for peer in _peers():
		rpc_id(peer, "rpc_died", peer_id, killer_id)
	rpc_died(peer_id, killer_id)
func _send_respawn(peer_id: int) -> void:
	for peer in _peers():
		rpc_id(peer, "rpc_respawn", peer_id)
	rpc_respawn(peer_id)
func _send_grant_stones(peer_id: int) -> void:
	for peer in _peers():
		rpc_id(peer, "rpc_grant_stones", peer_id)
	rpc_grant_stones(peer_id)
func _send_match_over(winner_id: int, final_kills: Dictionary) -> void:
	for peer in _peers():
		rpc_id(peer, "rpc_match_over", winner_id, final_kills)
	rpc_match_over(winner_id, final_kills)
# ---- 飞行物外观复制：射手那台机器把"我射出去了什么"广播给其他人 ----
# 只演样子（箭/魔法球/冰球），伤害仍然只在射手机器判定并上报房主结算
func send_fx(kind: String, pos: Vector3, vel: Vector3, payload: Dictionary = {}) -> void:
	for peer in _peers():
		rpc_id(peer, "rpc_spawn_fx", kind, pos, vel, payload)
@rpc("any_peer", "call_remote", "reliable")
func rpc_spawn_fx(kind: String, pos: Vector3, vel: Vector3, payload: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var known := false
	for p in PvpState.players:
		if int(p.id) == sender:
			known = true
			break
	if not known:
		return                      # 不在名单里的人发的不算
	REPLICA_SCRIPT.spawn(self, kind, pos, vel, payload)
# ---- 结果广播 ----
@rpc("authority", "call_local", "reliable")
func rpc_apply_hp(peer_id: int, value: float, attacker_id: int, weapon: String) -> void:
	var n := _player_node(peer_id)
	if n != null:
		n.call("apply_hp", value)
	# 命中播报只给射手本人看（意义就是"我这下打中了"）；流血跳血不播
	if multiplayer.get_unique_id() == attacker_id and weapon != "流血":
		hud.call("announce_hit", weapon, PvpState.name_of(peer_id))
@rpc("authority", "call_local", "reliable")
func rpc_died(victim_id: int, killer_id: int) -> void:
	var n := _player_node(victim_id)
	if n != null:
		n.call("set_dead", true)
	hud.call("announce_kill", PvpState.name_of(killer_id), PvpState.name_of(victim_id))
	if int(multiplayer.get_unique_id()) == victim_id:
		hud.call("_on_hp", 0.0, PvpState.MAX_HP)
	_update_scoreboard()
@rpc("authority", "call_local", "reliable")
func rpc_respawn(peer_id: int) -> void:
	var n := _player_node(peer_id)
	if n != null:
		n.call("apply_hp", PvpState.MAX_HP)
		n.call("set_dead", false)
	if int(multiplayer.get_unique_id()) == peer_id:
		hud.call("clear_death_tag")
@rpc("authority", "call_local", "reliable")
func rpc_grant_stones(peer_id: int) -> void:
	# 只有击杀者本人的机器往背包里放石头
	if int(multiplayer.get_unique_id()) != peer_id:
		return
	var my_inv := get_node_or_null("HUD/Inventory")
	if my_inv != null and my_inv.has_method("add_item"):
		my_inv.call("add_item", "stone", PvpState.KILL_STONES)
@rpc("any_peer", "call_remote", "reliable")
func rpc_apply_stun(peer_id: int, sec: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return                  # 只有房主能定人
	if int(multiplayer.get_unique_id()) != peer_id:
		return
	var n := _player_node(peer_id)
	if n != null:
		n.call("apply_stun", sec)
@rpc("authority", "call_local", "reliable")
func rpc_match_over(winner_id: int, final_kills: Dictionary) -> void:
	_over = true
	var lines := "%s 达到 %d 杀，获得胜利！\n" % [PvpState.name_of(winner_id), int(final_kills.get(winner_id, 0))]
	for i in PvpState.players.size():
		var pid := int(PvpState.players[i].id)
		lines += "%s：%d 杀\n" % [String(PvpState.players[i].name), int(final_kills.get(pid, 0))]
	hud.call("announce", lines, Color(1, 0.9, 0.4))
	var back := Button.new()
	back.text = "回到主页"
	back.position = Vector2(640 - 70, 420)
	back.custom_minimum_size = Vector2(140, 44)
	back.pressed.connect(func():
		multiplayer.multiplayer_peer = null
		PvpState.reset()
		get_tree().change_scene_to_file(MENU_SCENE))
	hud.add_child(back)
# ---- 房主：击杀与胜负 ----
func _on_kill(victim_id: int, killer_id: int) -> void:
	if victim_id == killer_id:
		kills[victim_id] = maxi(int(kills[victim_id]) - 1, 0)   # 没有自杀刷分
	else:
		kills[killer_id] = int(kills.get(killer_id, 0)) + 1
		_send_grant_stones(killer_id)
	_send_died(victim_id, killer_id)
	_update_scoreboard()
	if int(kills[killer_id]) >= PvpState.WIN_KILLS:
		_over = true
		_send_match_over(killer_id, kills.duplicate())
		return
	get_tree().create_timer(PvpState.RESPAWN_WAIT).timeout.connect(func():
		if _over or not is_inside_tree() or not multiplayer.is_server():
			return
		hp[victim_id] = PvpState.MAX_HP
		_send_respawn(victim_id))
func _update_scoreboard() -> void:
	var lines := ""
	for i in PvpState.players.size():
		var pid := int(PvpState.players[i].id)
		lines += "%s %d杀   " % [String(PvpState.players[i].name), int(kills.get(pid, 0))]
	hud.call("set_scoreboard", lines)
