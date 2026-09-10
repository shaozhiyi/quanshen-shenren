extends SceneTree
## 弓箭蓄力输入自检（左键 / X 等效）：
##  1) 按住 X 会蓄力，松手发射（本次新增）
##  2) 按住左键仍然蓄力发射（回归）
##  3) 任一按下都起手；按住 X 再点左键后先放开 X，蓄力既不断也不清零，而且只射一支
##  4) 射击冷却中按下不起手（两条输入一样），冷却结束又能起手
##  5) 换回剑之后弓不再响应 X（两把武器共用 X 不冲突）
## 必须窗口模式跑：左键那条路要求 Input.mouse_mode == CAPTURED，headless 下拿不到。
## 蓄力计时靠手动 _process(0.1) 推进（帧率不固定，按帧等会飘）。

const ARROW_SCRIPT := preload("res://scripts/arrow.gd")
const DT := 0.1

var fails: Array[String] = []
var bow: Node


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


## 手动推进弓的计时（测试里已把它的 _process 关掉，避免和引擎重复累加）
func _tick(times: int) -> void:
	for _i in times:
		bow.call("_process", DT)


func _key(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_X
	ev.physical_keycode = KEY_X
	ev.pressed = pressed
	ev.echo = false
	bow.call("_unhandled_input", ev)


func _lmb(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	bow.call("_unhandled_input", ev)


func _arrows() -> int:
	return (ARROW_SCRIPT._active as Array).size()


func _charging() -> bool:
	return bool(bow.call("is_charging"))


func _ratio() -> float:
	return float(bow.call("charge_ratio"))


func _run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 88108)
	root.add_child(w)
	await _frames(30)
	var player := w.get_node("Player")
	bow = w.get_node("Player/Camera3D/Bow")
	var sword := w.get_node("Player/Camera3D/Sword")
	chk(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "鼠标已捕获（左键那条路的前提）")
	player.call("set_current_weapon", 1)
	await _frames(2)
	bow.process_mode = Node.PROCESS_MODE_DISABLED
	chk(bool(bow.call("is_active")), "已装备弓")
	chk(not bool(sword.get("active")), "剑同时收起（不会抢 X 的输入）")

	# ---- 1. X 蓄力 → 松手发射 ----
	var n0 := _arrows()
	_key(true)
	chk(_charging(), "按下 X 就进入蓄力")
	_tick(5)
	chk(absf(_ratio() - 0.25) < 0.02, "按住 X 半秒 → 蓄力 25%%（实测 %.0f%%）" % [_ratio() * 100.0])
	_tick(15)
	chk(absf(_ratio() - 1.0) < 0.01, "再按满 2 秒 → 蓄满（实测 %.0f%%）" % [_ratio() * 100.0])
	_key(false)
	chk(not _charging(), "放开 X 就撒放")
	chk(float(bow.get("_cooldown")) > 0.0, "撒放后进入射击冷却")
	chk(_arrows() == n0 + 1, "确实生成了一支箭（%d → %d）" % [n0, _arrows()])

	# ---- 2. 左键回归 ----
	bow.set("_cooldown", 0.0)
	n0 = _arrows()
	_lmb(true)
	chk(_charging(), "按住左键仍然蓄力")
	_tick(10)
	_lmb(false)
	chk(not _charging(), "左键松手发射")
	chk(_arrows() == n0 + 1, "左键这一射也生成了一支箭（%d → %d）" % [n0, _arrows()])

	# ---- 3. 两个输入叠加：先放 X 不断蓄力、且蓄力不被清零、只射一支 ----
	bow.set("_cooldown", 0.0)
	n0 = _arrows()
	_key(true)
	_tick(5)                                            # 0.5 秒
	_lmb(true)                                          # 中途又按下左键
	_tick(5)                                            # 0.5 秒
	_key(false)                                         # 先放开 X
	chk(_charging(), "左键还按着 → 放开 X 蓄力不能中断")
	chk(absf(_ratio() - 0.5) < 0.02,
		"蓄力连续累加没被清零（1.0 秒应 50%%，实测 %.0f%%）" % (_ratio() * 100.0))
	_tick(5)
	_lmb(false)
	chk(_arrows() == n0 + 1, "最后一个输入放开才发射（这一轮只射出 1 支）")

	# ---- 4. 冷却中不起手 ----
	chk(float(bow.get("_cooldown")) > 0.0, "刚射完还在冷却")
	_key(true)
	chk(not _charging(), "冷却中按 X 不起手")
	_key(false)
	_lmb(true)
	chk(not _charging(), "冷却中按左键也不起手")
	_lmb(false)
	bow.set("_cooldown", 0.0)
	_key(true)
	chk(_charging(), "冷却结束后再按就正常起手")
	_key(false)
	bow.set("_cooldown", 0.0)

	# ---- 5. 换回剑：弓不再吃 X ----
	player.call("set_current_weapon", 0)
	await _frames(2)
	chk(not bool(bow.call("is_active")), "已换回剑")
	_key(true)
	chk(not _charging(), "剑在手时按 X 不会偷偷给弓蓄力")
	_key(false)
	chk(bool(sword.get("active")), "剑是 active 的（X 归它挥砍）")
	_done()


func _done() -> void:
	print("\n== 弓箭蓄力自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
