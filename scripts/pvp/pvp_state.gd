extends Object
class_name PvpState
## 局域网 PVP 的跨场景状态：大厅里填好，竞技场里读。
## 用 class_name 静态变量（不是节点），切场景不会丢、也不用注册 autoload。
## 房间规则：纯数字 4 位房间号；2~4 人（含房主）；房主开始后锁门；
## 单打独斗（每人一队）；每人 700 血；击杀一人得 2 块强化石。
const PORT := 24565              # ENet 联机端口
const DISC_PORT := 24566         # UDP 房间广播端口
const MAX_PLAYERS := 4           # 含房主
const MIN_PLAYERS := 2           # 房主可开始的最少人数
const MAX_HP := 700.0            # PVP 每人血量（与单机 100 区分）
const KILL_STONES := 2           # 击杀一人奖励的强化石
const WIN_KILLS := 10            # 先到 10 杀获胜
const RESPAWN_WAIT := 3.0        # 阵亡后重生等待秒数
const MAPS := ["山地", "空白", "国道"]
static var room_code := ""       # 4 位数字房间号（房主自定义）
static var map_name := "空白"    # 房主选的地图
static var players: Array = []   # [{id:int, name:String}]，房主（id=1）永远第一位
static var started := false      # 房主是否已点开始（开始后锁门）
static func reset() -> void:
	room_code = ""
	map_name = "空白"
	players = []
	started = false
static func name_of(peer_id: int) -> String:
	## 玩家显示名：按大厅座次叫 玩家1/玩家2…（找不到就报 id）
	for p in players:
		if int(p.id) == peer_id:
			return String(p.name)
	return "玩家%d" % peer_id
static func seat_of(peer_id: int) -> int:
	## 座次（从 1 开始）：决定出生点顺序
	for i in players.size():
		if int(players[i].id) == peer_id:
			return i + 1
	return 1
static func host_id() -> int:
	return 1   # ENet 约定：开服务器的那台永远是 1
