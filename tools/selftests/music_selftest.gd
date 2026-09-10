extends SceneTree
## 大运战斗配乐接线自检：
##  1) 名册 song 指向新放进来的 assets/audio/song_truck.mp3，文件确实存在
##  2) 载具档 = 整场背景乐：MP3 被改成从头连续循环，进战场立刻开播
##  3) 撤退 / 击杀都会停乐（不会留一段音乐在大地图或尸体上继续放）
##  4) 狗奶那档不受影响：仍是只放一遍副歌、由相位机自己起头，进战不自动播
## 必须窗口模式跑（headless 下 AudioStreamPlayer.playing 不可信）。

var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	chk(ResourceLoader.exists("res://assets/audio/song_truck.mp3"), "新歌在 assets/audio/song_truck.mp3")
	var ROSTER: GDScript = load("res://scripts/boss_roster.gd")
	var dtruck: Dictionary = ROSTER.def("truck")
	chk(String(dtruck.get("song", "")) == "res://assets/audio/song_truck.mp3",
		"名册：大运 song 指向新歌（%s）" % String(dtruck.get("song", "")))

	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 88105)
	root.add_child(w)
	await _frames(30)
	var player := w.get_node("Player")
	var truck: Node = null
	var milk: Node = null
	for b in player.call("bosses"):
		if String(b.get("def_id")) == "truck":
			truck = b
		if String(b.get("def_id")) == "dogmilk":
			milk = b
	chk(truck != null and milk != null, "两只 BOSS 都在场")
	if truck == null or milk == null:
		_done()
		return

	chk(bool(truck.get("_has_music")), "大运检测到配乐文件")
	var tstream: AudioStreamMP3 = (truck.get("_music") as AudioStreamPlayer).stream
	chk(tstream != null, "大运的 AudioStreamPlayer 已挂上流")
	chk(bool(tstream.loop), "载具档 = 循环背景乐（AudioStreamMP3.loop 已开）")
	chk(not bool(truck.get("_has_skills")), "大运仍是载具档（不走乐句时间轴）")

	var mstream: AudioStreamMP3 = (milk.get("_music") as AudioStreamPlayer).stream
	chk(mstream == null or not bool(mstream.loop),
		"狗奶那首仍只走一遍副歌，没被顺手改成循环")

	# ---- 进战即开唱 ----
	chk(not (truck.get("_music") as AudioStreamPlayer).playing, "开战前是安静的")
	truck.call("set_arena_mode", true)
	await _frames(3)
	chk((truck.get("_music") as AudioStreamPlayer).playing, "进战场立刻开始放歌")
	var pos0: float = (truck.get("_music") as AudioStreamPlayer).get_playback_position()
	chk(pos0 < 1.0, "是从头起的（当前 %.2f 秒）" % pos0)
	milk.call("set_arena_mode", true)
	await _frames(3)
	chk(not (milk.get("_music") as AudioStreamPlayer).playing, "狗奶进战不自动播（仍等前摇）")
	milk.call("set_arena_mode", false)

	# ---- 撤退停乐 ----
	truck.call("set_arena_mode", false)
	await _frames(3)
	chk(not (truck.get("_music") as AudioStreamPlayer).playing, "撤退立刻停乐")

	# ---- 击杀停乐 ----
	truck.call("set_arena_mode", true)
	await _frames(3)
	truck.call("take_damage", 99999)
	await _frames(3)
	chk(bool(truck.call("is_dead")), "大运已阵亡")
	chk(not (truck.get("_music") as AudioStreamPlayer).playing, "击杀瞬间停乐")
	_done()


func _done() -> void:
	print("\n== 配乐自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
