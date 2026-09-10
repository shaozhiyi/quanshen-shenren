extends Node
## 诊断落盘（自动加载单例 Diag）：把"哪边卡了"变成几个文件，发过来就能直接判。
##
## 日志都落在 user://logs/（Windows 上是 %APPDATA%\Godot\app_userdata\全是神人\logs）：
##   godot.log    引擎自己的报错与警告。由 project.godot 里 debug/file_logging 打开，
##                引擎自动写并轮转，SCRIPT ERROR 全在里面。
##   diag-*.log   本脚本写的：启动横幅 + 每 5 秒一行心跳（帧率/场景/血量/联机人数）。
##   shot-*.png   按 F12 存的当前画面。
##
## 热键：F12 = 存截图 + 一份状态快照；F11 = 打开日志文件夹。
## 只读不写游戏状态，任何一项取不到就跳过，绝不因为诊断把游戏弄崩。

const HEARTBEAT := 5.0        # 心跳间隔（秒）
const MAX_SHOTS := 12         # 截图最多留几张，超了把最旧的改名成 .old（不删）

var _dir := ""
var _diag_path := ""
var _acc := 0.0
var _boot := 0


func _ready() -> void:
	# 背包打开时整棵树是暂停的，诊断得照写；菜单与加载期也要有记录
	process_mode = Node.PROCESS_MODE_ALWAYS
	_boot = Time.get_ticks_msec()
	var dir := OS.get_user_data_dir().path_join("logs")
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("Diag: 建日志目录失败 " + error_string(err))
		return
	_dir = dir
	var stam := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "T")
	_diag_path = _dir.path_join("diag-" + stam + ".log")
	_line("=== 全是神人 诊断启动 ===")
	_line("引擎   : " + _version_text())
	_line("平台   : " + OS.get_name() + " " + Engine.get_architecture_name())
	_line("渲染   : " + String(RenderingServer.get_current_rendering_method())
		+ "  窗口 " + str(DisplayServer.window_get_size())
		+ "  3D缩放 " + str(ProjectSettings.get_setting("rendering/scaling_3d/scale")))
	_line("日志目录: " + _dir)
	_line(_heartbeat_line())
	_prune_diags()


## 心跳日志攒够 10 份后，把更旧的改名成 .old（不删，跟引擎轮转 godot.log 一个意思）
func _prune_diags() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	var logs: Array[String] = []
	for f in d.get_files():
		if f.begins_with("diag-") and f.ends_with(".log"):
			logs.append(f)
	if logs.size() <= 10:
		return
	logs.sort()
	for i in logs.size() - 10:
		d.rename(logs[i], logs[i] + ".old")


func _process(delta: float) -> void:
	if _diag_path == "":
		return
	_acc += delta
	if _acc < HEARTBEAT:
		return
	_acc = 0.0
	_line(_heartbeat_line())


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_F12:
		dump_now()
	elif k.keycode == KEY_F11:
		open_logs()


## 存一张当前画面 + 一份完整状态快照，返回日志目录
func dump_now() -> String:
	var stam := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "T")
	_line("---- F12 手动快照 " + stam + " ----")
	_line(_full_state())
	var img := _grab()
	if img == null:
		_line("截图   : 拿不到画面（无头模式？）")
	else:
		var png := _dir.path_join("shot-" + stam + ".png")
		var e := img.save_png(png)
		_line("截图   : " + png + ("" if e == OK else "  失败 " + error_string(e)))
		_prune_shots()
	print("[Diag] 快照已写入 " + _dir)
	return _dir


## 在文件管理器里打开日志目录
func open_logs() -> void:
	if _dir == "":
		return
	var e := OS.shell_open(_dir)
	print("[Diag] 打开日志目录 " + _dir + ("" if e == OK else "  失败 " + error_string(e)))


func _heartbeat_line() -> String:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var ms: float = 0.0 if fps <= 0.0 else 1000.0 / fps
	var draw: int = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var prim: int = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var nodes: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	return "心跳 t=%5.1fs fps=%5.1f ms=%5.2f 绘制=%d 三角=%d 节点=%d | %s | %s | %s" % [
		float(Time.get_ticks_msec() - _boot) / 1000.0, fps, ms, draw, prim, nodes,
		_scene_text(), _player_text(), _pvp_text()]


func _full_state() -> String:
	var mem: int = Performance.get_monitor(Performance.MEMORY_STATIC)
	var objs: int = Performance.get_monitor(Performance.OBJECT_COUNT)
	var res: int = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	return "内存静态=%dKB 对象=%d 资源=%d | %s | %s | %s" % [
		mem / 1024, objs, res, _scene_text(), _player_text(), _pvp_text()]


func _line(s: String) -> void:
	if _diag_path == "":
		return
	var f := FileAccess.open(_diag_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_diag_path, FileAccess.WRITE)
	if f == null:
		push_warning("Diag: 写不了日志 " + error_string(FileAccess.get_open_error()))
		return
	f.seek_end()
	f.store_line(Time.get_time_string_from_system() + " | " + s)
	f.close()


func _version_text() -> String:
	var v: Dictionary = Engine.get_version_info()
	return "%s.%s.%s %s (%s)" % [str(v.get("major")), str(v.get("minor")), str(v.get("patch")),
		str(v.get("status")), str(v.get("build"))]


func _scene_text() -> String:
	var cs := get_tree().current_scene
	return "场景=" + (String(cs.name) if cs != null else "<无>")


func _player_text() -> String:
	var pl := _local_player()
	if pl == null:
		return "玩家=<无>"
	var pos: Vector3 = pl.global_position
	var hp: float = _num(pl, "hp", -1.0)
	var mx: float = _num(pl, "max_hp", -1.0)
	var mp: float = _num(pl, "mp", -1.0)
	var sp: float = pl.call("speed_now") if pl.has_method("speed_now") else -1.0
	var extra := ""
	if _num(pl, "dash_cd", -999.0) > -900.0:
		extra = " 冲刺冷却%.2f" % _num(pl, "dash_cd", 0.0)
	return "玩家 hp=%.0f/%.0f mp=%.0f 速度=%.1f 位置=(%.1f,%.1f,%.1f)%s" % [
		hp, mx, mp, sp, pos.x, pos.y, pos.z, extra]


## 取一个数值属性；没有该属性（或不是数字）时回 fallback
func _num(o: Object, prop: String, fallback: float) -> float:
	var v = o.get(prop)
	return float(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else fallback


## 联机里玩家组有一堆远程玩家，优先挑本机有权威的那个；单机直接就是唯一那个
func _local_player() -> Node:
	var list := get_tree().get_nodes_in_group("player")
	for n in list:
		var nd := n as Node
		if nd != null and nd.has_method("is_multiplayer_authority") and bool(nd.call("is_multiplayer_authority")):
			return nd
	return null if list.is_empty() else (list[0] as Node)


func _pvp_text() -> String:
	var room := String(PvpState.room_code)
	var who := ""
	for p in PvpState.players:
		var d := p as Dictionary
		if d == null:
			continue
		who += "%s:%s " % [str(d.get("id")), String(d.get("name"))]
	return "联机 房间=%s 我=%d 远端=%d 名册=%d人[%s] 地图=%s" % [
		room if room != "" else "-", multiplayer.get_unique_id(),
		multiplayer.get_peers().size(), PvpState.players.size(), who.strip_edges(),
		String(PvpState.map_name)]


func _grab() -> Image:
	var vp := get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()


## 截图攒够了把最旧的挪成 .old（不删，玩家想留着对比也行）
func _prune_shots() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	var pngs: Array[String] = []
	for f in d.get_files():
		if f.begins_with("shot-") and f.ends_with(".png"):
			pngs.append(f)
	if pngs.size() <= MAX_SHOTS:
		return
	pngs.sort()
	var over: int = pngs.size() - MAX_SHOTS
	for i in over:
		d.rename(pngs[i], pngs[i] + ".old")
