extends SceneTree
## 定身 × 战斗配乐：BOSS 被蓝球定住的那一两秒，歌要跟着一起掐住，
## 时间一到接着打、接着唱（不是重头放，也不是把这一段跳过去）。
##  1) 定身瞬间 stream_paused 打开，播放位置不再前进
##  2) 定身期间动作（_phase_t）和歌一起冻住
##  3) 定身结束自动解冻，歌从掐住那一拍继续，动作也继续
##  4) 定身中击杀 / 撤退：停乐且不把暂停标记留给下一场（否则下一场是哑巴）
## 必须窗口模式跑（headless 下 AudioStreamPlayer 不可信）。

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


func _boss(w: Node, id: String) -> Node:
	for b in w.get_node("Player").call("bosses"):
		if String(b.get("def_id")) == id:
			return b
	return null


func _run() -> void:
	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 88105)
	root.add_child(w)
	await _frames(40)
	var truck := _boss(w, "truck")
	var milk := _boss(w, "dogmilk")
	chk(truck != null and milk != null, "两只 BOSS 都在场")
	if truck == null or milk == null:
		_done()
		return
	var tm: AudioStreamPlayer = truck.get("_music")
	var mm: AudioStreamPlayer = milk.get("_music")

	# ---- 1~3. 载具档：进战循环乐跟着一起冻、一起续 ----
	truck.call("set_arena_mode", true)
	await _frames(6)
	chk(tm.playing and not tm.stream_paused, "大运进战场即开乐（没被掐着）")
	truck.call("stun", 2.0)
	await _frames(4)
	chk(tm.stream_paused and not tm.playing, "定身瞬间歌立刻停（playing=false，但位置留着）")
	var p0: float = tm.get_playback_position()
	await _frames(40)
	var p1: float = tm.get_playback_position()
	chk(absf(p1 - p0) < 0.06, "定身期间播放位置不动（%.2f → %.2f）" % [p0, p1])
	truck.set("_stun_t", 0.0)         # 直接结束定身（走 _process 的解冻分支）
	await _frames(10)
	chk(not tm.stream_paused, "定身结束自动解冻")
	var p2: float = tm.get_playback_position()
	chk(absf(p2 - p1) < 0.2, "解冻就在原地接着放（%.2f → %.2f，没跳拍也没重头）" % [p1, p2])
	await _frames(40)
	chk(tm.get_playback_position() > p2 + 0.3,
		"接着唱：从 %.2f 秒继续往前放" % p2)
	truck.call("set_arena_mode", false)
	await _frames(3)
	chk(not tm.playing and not tm.stream_paused, "撤退停乐且不残留暂停标记")

	# ---- 4. 技能档：副歌 + 动作一起冻 ----
	milk.call("set_arena_mode", true)
	milk.set("_phase", 0)
	milk.set("_phase_t", 7.9)          # 0.1 秒后升空前摇 → 起歌
	await _frames(20)
	chk(mm.playing and not mm.stream_paused, "狗奶前摇起点自动起歌")
	milk.call("stun", 2.0)
	await _frames(6)
	var mp: float = mm.get_playback_position()
	var pt: float = milk.get("_phase_t")
	chk(mm.stream_paused, "定身瞬间副歌也掐住")
	await _frames(50)
	chk(absf(float(mm.get_playback_position()) - mp) < 0.06,
		"歌冻住（%.2f → %.2f）" % [mp, mm.get_playback_position()])
	chk(absf(float(milk.get("_phase_t")) - pt) < 1e-6,
		"动作一起冻住（相位计时仍是 %.2f 秒）" % float(milk.get("_phase_t")))
	milk.set("_stun_t", 0.0)
	await _frames(10)
	chk(not mm.stream_paused and mm.playing, "定身结束接着唱")
	chk(float(milk.get("_phase_t")) > pt, "动作也接着推进（%.2f → %.2f）" % [pt, float(milk.get("_phase_t"))])

	# ---- 5. 定身中击杀：停乐 + 清标记，别把下一场变成哑巴 ----
	milk.call("stun", 3.0)
	await _frames(4)
	chk(mm.stream_paused, "再次定身，歌掐住")
	milk.call("take_damage", 999999)
	await _frames(3)
	chk(bool(milk.call("is_dead")), "狗奶已阵亡")
	chk(not mm.playing and not mm.stream_paused and not bool(milk.get("_music_frozen")),
		"击杀瞬间停乐并销掉暂停标记")
	milk.call("set_arena_mode", false)
	await _frames(3)
	milk.call("set_arena_mode", true)      # 复活再开一场：歌必须还能正常起头
	milk.set("_phase", 0)
	milk.set("_phase_t", 7.9)
	await _frames(20)
	chk(mm.playing and not mm.stream_paused, "重开一场歌照常起头（没被旧标记哑掉）")
	_done()


func _done() -> void:
	print("\n== 定身×音乐自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
