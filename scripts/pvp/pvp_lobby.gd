extends Control
## 局域网 PVP 大厅：创建房间（自定义 4 位数字房号 + 选地图）／加入房间（输入房号自动搜索）。
## 房主开始后所有人切进竞技场；联机协商全靠 ENet（房主当服务器），本场景只管"攒人"。
## 网络对端约定：本节点路径两边一致（/root/PvpLobby），RPC 全走 SceneTree 默认 MultiplayerAPI。

const ARENA_SCENE := "res://scenes/pvp_arena.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

var _disc: PvpDiscovery
var _status: Label
var _room_edit: LineEdit          # 创建用：房间号
var _join_edit: LineEdit          # 加入用：房间号
var _map_opt: OptionButton
var _create_btn: Button
var _join_btn: Button
var _create_box: VBoxContainer
var _join_box: VBoxContainer
var _lobby_box: VBoxContainer
var _panel_bg: Panel
var _player_list: Label
var _start_btn: Button
var _join_note: Label
var _join_candidates: Dictionary = {}   # 搜到的房号 → ip（点列表里那条加入）
var _search_accum := 0.0
var _am_host := false
var _closing := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	PvpState.reset()
	_build_ui()


func _exit_tree() -> void:
	# 离开大厅（进了竞技场 / 返回主页）就停广播；ENet 连接本身挂在 SceneTree 上，
	# 进竞技场后继续用，这里绝不能断。
	if _disc != null:
		_disc.stop()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "联机对战 · 局域网"
	title.position = Vector2(0, 40)
	title.size = Vector2(1280, 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.72))
	add_child(title)

	var tip := Label.new()
	tip.text = "必须连同一个局域网（Wi-Fi 得允许设备互访）· 没有服务器：开房那台电脑就是主机 · 房主退出 = 房间解散"
	tip.position = Vector2(0, 100)
	tip.size = Vector2(1280, 22)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 14)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	add_child(tip)

	_status = Label.new()
	_status.position = Vector2(0, 620)
	_status.size = Vector2(1280, 24)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	add_child(_status)

	var back := Button.new()
	back.text = "返回主页"
	back.position = Vector2(20, 660)
	back.custom_minimum_size = Vector2(120, 40)
	back.pressed.connect(_on_back)
	add_child(back)

	# ---- 创建房间面板 ----
	_create_box = _panel(Vector2(640 - 350, 170), "创建房间（你是房主）")
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	_create_box.add_child(row1)
	row1.add_child(_mk_label("房间号(4位数字)："))
	_room_edit = LineEdit.new()
	_room_edit.placeholder_text = "例如 2026"
	_room_edit.max_length = 4
	_room_edit.custom_minimum_size = Vector2(120, 34)
	_room_edit.add_theme_font_size_override("font_size", 18)
	row1.add_child(_room_edit)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_create_box.add_child(row2)
	row2.add_child(_mk_label("地图："))
	_map_opt = OptionButton.new()
	for m in PvpState.MAPS:
		_map_opt.add_item(m)
	_map_opt.custom_minimum_size = Vector2(120, 34)
	row2.add_child(_map_opt)
	_create_btn = _mk_btn("创建房间")
	_create_btn.pressed.connect(_on_create)
	_create_box.add_child(_create_btn)
	var rule := Label.new()
	rule.text = "规则：单打独斗（人手一队）· 每人 700 血 · 初始剑+弓（法杖、狗奶在背包）\n击杀一人得 2 块强化石 · 先到 %d 杀获胜 · 最少 %d 人开局，房主点开始后锁门" % [PvpState.WIN_KILLS, PvpState.MIN_PLAYERS]
	rule.add_theme_font_size_override("font_size", 13)
	rule.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.custom_minimum_size = Vector2(288, 0)
	_create_box.add_child(rule)

	# ---- 加入房间面板 ----
	_join_box = _panel(Vector2(640 + 30, 170), "加入房间")
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 8)
	_join_box.add_child(row3)
	row3.add_child(_mk_label("房间号："))
	_join_edit = LineEdit.new()
	_join_edit.placeholder_text = "4 位数字"
	_join_edit.max_length = 4
	_join_edit.custom_minimum_size = Vector2(120, 34)
	_join_edit.add_theme_font_size_override("font_size", 18)
	row3.add_child(_join_edit)
	var search := _mk_btn("搜索")
	search.pressed.connect(_on_search)
	row3.add_child(search)
	_join_note = Label.new()
	_join_note.text = "同一局域网内会自动听到房间的广播，不用知道对方 IP"
	_join_note.add_theme_font_size_override("font_size", 13)
	_join_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_join_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_note.custom_minimum_size = Vector2(300, 60)
	_join_box.add_child(_join_note)

	# ---- 大厅状态面板（创建/加入成功后出现）----
	_panel_bg = _panel_bg_only(Vector2(640 - 260, 170))
	_lobby_box = VBoxContainer.new()
	_lobby_box.position = Vector2(640 - 236, 190)
	_lobby_box.custom_minimum_size = Vector2(472, 0)
	_lobby_box.add_theme_constant_override("separation", 10)
	add_child(_lobby_box)
	_player_list = Label.new()
	_player_list.add_theme_font_size_override("font_size", 18)
	_player_list.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_lobby_box.add_child(_player_list)
	_start_btn = _mk_btn("开始游戏（至少 2 人）")
	_start_btn.pressed.connect(_on_start)
	_lobby_box.add_child(_start_btn)
	var leave := _mk_btn("解散并返回主页")
	leave.pressed.connect(_on_back)
	_lobby_box.add_child(leave)
	_panel_bg.visible = false          # 大厅状态面板：创建/加入成功后才出现
	_lobby_box.visible = false

	_disc = PvpDiscovery.new()
	add_child(_disc)


func _panel(pos: Vector2, title_text: String) -> VBoxContainer:
	var bg := _panel_bg_only(pos)
	var box := VBoxContainer.new()
	box.position = pos + Vector2(16, 14)
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(1, 0.95, 0.72))
	box.add_child(t)
	return box


func _panel_bg_only(pos: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = Vector2(320, 400)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.92)
	sb.border_color = Color(0.52, 0.46, 0.28, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	return l


func _mk_btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 36)
	b.add_theme_font_size_override("font_size", 16)
	return b


## 现在是否已在房间里：注意 Godot 默认的 multiplayer_peer 不是 null 而是
## OfflineMultiplayerPeer（离线单机也有"服务器"身份），按 null 判断永远误判。
func _in_room() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


## 主页返回：房主/成员都断线，回主页
func _on_back() -> void:
	_closing = true
	multiplayer.multiplayer_peer = null
	PvpState.reset()
	get_tree().change_scene_to_file(MENU_SCENE)


# ---- 创建房间（房主）----
func _on_create() -> void:
	var code := _room_edit.text.strip_edges()
	if code.length() != 4 or not code.is_valid_int():
		_status.text = "房间号必须是 4 位数字"
		return
	if _in_room():
		_status.text = "已经在一间房里了"
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PvpState.PORT, PvpState.MAX_PLAYERS - 1)
	if err != OK:
		_status.text = "开房失败：%s（端口被占用？）" % error_string(err)
		return
	multiplayer.multiplayer_peer = peer
	_am_host = true
	PvpState.room_code = code
	PvpState.map_name = PvpState.MAPS[_map_opt.selected]
	PvpState.players = [{"id": 1, "name": "玩家1"}]
	_disc.start_host_broadcast(int(code), PvpState.map_name, 1)
	_multiplayer_hooks()
	_show_lobby()
	_status.text = "房间 %s 已开（%s）。把房号告诉朋友，他们点「加入房间」就能搜到" % [code, PvpState.map_name]


# ---- 加入房间（成员）----
func _on_search() -> void:
	var code := _join_edit.text.strip_edges()
	if code.length() != 4 or not code.is_valid_int():
		_status.text = "房间号必须是 4 位数字"
		return
	if _in_room():
		_status.text = "已经在一间房里了"
		return
	# 已经听到这个房间的广播 → 直接加入；否则开始监听
	if _disc != null and _disc.found.has(int(code)):
		_try_join_room(int(code))
		return
	_disc.start_listen()
	_join_candidates.clear()
	_status.text = "正在局域网里喊话找房间 %s…（房主开着房的话几秒内就能听到，再点一次「搜索」加入）" % code
	_join_note.text = "搜到了会显示在这里，再点一次「搜索」即可加入"


func _try_join_room(room: int) -> void:
	var info: Dictionary = _disc.pick(room)
	if info.is_empty():
		_status.text = "局域网里没听到房间 %s 的广播（房主开房了吗？在同一网络里吗？）" % room
		return
	join_ip(String(info.ip), room)


## 直接连 IP 加入（发现机制填进来，自检也走这里）
func join_ip(ip: String, room: int) -> void:
	if _in_room():
		_status.text = "已经在一间房里了"
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PvpState.PORT)
	if err != OK:
		_status.text = "连接失败：%s" % error_string(err)
		return
	multiplayer.multiplayer_peer = peer
	PvpState.room_code = "%04d" % room
	_multiplayer_hooks()
	_status.text = "正在连接 %s …" % ip
	_join_note.text = "连上后会出现在房间的玩家列表里"


# ---- ENet 事件 ----
func _multiplayer_hooks() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)


func _on_peer_connected(id: int) -> void:
	# 只有房主管人：等对方报到来
	pass


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_drop_player(id)


func _on_connected() -> void:
	# 告诉房主"我来了"（在自己的大厅节点上发 RPC），名字房主定
	rpc_id(1, "rpc_register")
	_status.text = "已连上房主的电脑，等房主分配座位…"


func _on_connect_failed() -> void:
	multiplayer.multiplayer_peer = null
	_status.text = "连不上：房主不在线或端口不通"


func _on_server_lost() -> void:
	multiplayer.multiplayer_peer = null
	PvpState.reset()
	get_tree().change_scene_to_file(MENU_SCENE)


# ---- 房主侧 RPC：成员报到来 ----
@rpc("any_peer", "call_remote", "reliable")
func rpc_register() -> void:
	if not multiplayer.is_server() or PvpState.started:
		return
	var id := multiplayer.get_remote_sender_id()
	for p in PvpState.players:
		if int(p.id) == id:
			return                     # 重复报到忽略
	if PvpState.players.size() >= PvpState.MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var nm := "玩家%d" % (PvpState.players.size() + 1)
	PvpState.players.append({"id": id, "name": nm})
	_disc.update_host_info(PvpState.players.size(), PvpState.map_name)
	_sync_lobby()


## 房主把最新玩家名单广播给所有人（call_local：房主自己也刷新）
@rpc("authority", "call_local", "reliable")
func rpc_lobby(players: Array, map_name: String) -> void:
	PvpState.players = players
	PvpState.map_name = map_name
	_show_lobby()


## 房主点开始：全员切竞技场
@rpc("authority", "call_local", "reliable")
func rpc_start(map_name: String, players: Array) -> void:
	PvpState.map_name = map_name
	PvpState.players = players
	PvpState.started = true
	if _disc != null:
		_disc.stop()
	for p in players:
		if int(p.id) != 1 and int(p.id) != multiplayer.get_unique_id():
			rpc_id(int(p.id), "rpc_start", map_name, players)
	get_tree().change_scene_to_file(ARENA_SCENE)


## 满员/已开局时房主把人踢回去
func _drop_player(id: int) -> void:
	for i in PvpState.players.size():
		if int(PvpState.players[i].id) == id:
			PvpState.players.remove_at(i)
			break
	_disc.update_host_info(PvpState.players.size(), PvpState.map_name)
	_sync_lobby()


func _sync_lobby() -> void:
	# 名单先定向发给每个成员（发一版带错误码的，方便排查），再本地刷一遍
	for p in PvpState.players:
		var pid := int(p.id)
		if pid == 1 or pid == multiplayer.get_unique_id():
			continue
		rpc_id(pid, "rpc_lobby", PvpState.players, PvpState.map_name)
	rpc_lobby(PvpState.players, PvpState.map_name)


func _on_start() -> void:
	if not _am_host or not multiplayer.is_server():
		return
	if PvpState.players.size() < PvpState.MIN_PLAYERS:
		_status.text = "人还没到齐：最少 %d 人才能开始" % PvpState.MIN_PLAYERS
		return
	PvpState.started = true
	rpc_start(PvpState.map_name, PvpState.players)


func _show_lobby() -> void:
	_create_box.visible = false
	_join_box.visible = false
	_panel_bg.visible = true
	_lobby_box.visible = true
	_start_btn.visible = _am_host
	var lines := "房间 %s ｜ 地图 %s ｜ %d/%d 人\n" % [PvpState.room_code, PvpState.map_name,
		PvpState.players.size(), PvpState.MAX_PLAYERS]
	for i in PvpState.players.size():
		var mark := "（房主）" if int(PvpState.players[i].id) == 1 else ""
		lines += "%s %s\n" % [String(PvpState.players[i].name), mark]
	lines += "\n等房主点「开始游戏」。开局后锁门，中途不能再加入。"
	if not _am_host:
		lines += "\n\n房主点开始后自动进图。"
	_player_list.text = lines


var _lobby_beat := 0.0


func _process(delta: float) -> void:
	# 房主：名单心跳广播（每 2 秒）。加入瞬间的首包可能撞上对方还在连接的竞态，
	# 心跳能兜住，也顺便把人数变化推给所有成员。
	if _am_host and multiplayer.is_server() and not PvpState.started:
		_lobby_beat += delta
		if _lobby_beat >= 2.0:
			_lobby_beat = 0.0
			_sync_lobby()
	# 加入方：轮询广播，把搜到的房间显示出来；已听到目标房号时再点「搜索」= 加入
	if _disc != null and not _disc.found.is_empty() and not _am_host and multiplayer.multiplayer_peer == null:
		var code := _join_edit.text.strip_edges()
		if code.is_valid_int() and _disc.found.has(int(code)):
			var info: Dictionary = _disc.found[int(code)]
			_join_note.text = "听到房间 %s（%s 地图，%d 人）—— 再点一次「搜索」即可加入" % [
				code, String(info.map), int(info.count)]
			_join_candidates[int(code)] = String(info.ip)
