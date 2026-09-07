extends Node
class_name PvpDiscovery
## 局域网房间发现（无服务器）：房主每 0.5 秒向本网段广播一条"我在房间 XXXX"，
## 加入方监听广播并对上房间号——所以谁都不用知道对方的 IP。
## 同一套端口约定：广播走 UDP 24566，正式联机走 ENet 24565（见 PvpState）。
## 注意：必须同一局域网且路由器没开"客户端隔离"，否则互相听不见（大厅界面有提示）。

const GAME_TAG := "qrld_pvp_v1"   # 广播包身份（别的程序乱发 UDP 不会误认）

var _udp: PacketPeerUDP
var _room := 0
var _map := ""
var _count := 0
var _accum := 0.0
# 加入方视角：听到的房间 {房号: {ip:String, map:String, count:int, seen:float}}
var found := {}


## 房主侧：开始/停止广播自己的房间
func start_host_broadcast(room: int, map: String, count: int) -> void:
	stop()
	_room = room
	_map = map
	_count = count
	if _udp == null:
		_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	# 绑定任意本地端口发送即可；目标 = 全网广播的发现端口
	if not _udp.is_bound():
		_udp.bind(0)
	set_process(true)


func update_host_info(count: int, map: String) -> void:
	_count = count
	_map = map


func stop() -> void:
	_room = 0
	set_process(false)


## 加入方侧：只听广播（不需要先输入 IP），按房号对上后填进 found
func start_listen() -> void:
	stop()
	found.clear()
	if _udp == null:
		_udp = PacketPeerUDP.new()
	if not _udp.is_bound():
		var err := _udp.bind(PvpState.DISC_PORT)
		if err != OK:
			push_warning("PvpDiscovery: 广播端口 %d 被占用（%s）" % [PvpState.DISC_PORT, error_string(err)])
	set_process(true)


func _process(delta: float) -> void:
	if _udp == null:
		return
	# 房主：按节拍广播自己的房间
	if _room > 0:
		_accum += delta
		if _accum >= 0.5:
			_accum = 0.0
			var pkt := "%s|%d|%d|%s" % [GAME_TAG, _room, _count, _map]
			_udp.set_dest_address("255.255.255.255", PvpState.DISC_PORT)
			_udp.put_packet(pkt.to_utf8_buffer())
	# 加入方：收广播，记下"谁在哪个房间"
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet().get_string_from_utf8()
		var ip := _udp.get_packet_ip()
		var parts := pkt.split("|")
		if parts.size() < 4 or parts[0] != GAME_TAG:
			continue
		var room := int(parts[1])
		if room <= 0:
			continue
		found[room] = {"ip": ip, "map": parts[3], "count": int(parts[2]), "seen": Time.get_ticks_msec()}


## 加入方：按 4 位房间号取一个还活着的房间地址（6 秒内听到过才算活着）
func pick(room: int) -> Dictionary:
	var dead: Array = []
	var now := Time.get_ticks_msec()
	var out := {}
	for k in found:
		if now - int(found[k].seen) > 6000:
			dead.append(k)
	for k in dead:
		found.erase(k)
	if found.has(room):
		out = found[room]
	return out
