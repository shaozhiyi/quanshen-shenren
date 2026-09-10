extends SceneTree
## 切换武器上锁自检（本次新增规则：蓄力中 / 挥砍动画中不能按 C 切武器）
##  1) 剑：真实挥砍动画播放期间 C 无效，动画自己结束后 C 恢复可用
##  2) 弓：按住 X 蓄力期间 C 无效，且蓄力进度不被打断、松手照常射箭
##  3) 弓：按住左键蓄力期间同样拦住 C（两个输入源等价）
##  4) 手动置位两把武器的忙碌标记，确认 weapon_busy() 只认"手上这把"
##  5) 读档用的 set_current_weapon 不受锁限制（外部状态还原必须无条件生效）
## 必须窗口模式跑：左键那条路要求 Input.mouse_mode == CAPTURED。
## 弓的蓄力计时用手动 _process(0.1) 推进（帧率不固定，按帧等会飘）。

const ARROW_SCRIPT := preload("res://scripts/arrow.gd")
const DT := 0.1

var fails: Array[String] = []
var player: Node
var bow: Node
var sword: Node


func chk(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   | " + msg)
	else:
		fails.append(msg)
		print("  FAIL | " + msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _tick(times: int) -> void:
	for _i in times:
		bow.call("_process", DT)


func _key(pressed: bool, k: Key = KEY_X) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = pressed
	ev.echo = false
	# 弓只吃 _unhandled_input；C 走 player 的输入分支
	if k == KEY_C:
		player.call("_unhandled_input", ev)
	else:
		bow.call("_unhandled_input", ev)
		sword.call("_unhandled_input", ev)


func _lmb(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	bow.call("_unhandled_input", ev)


func _weapon() -> int:
	return int(player.get("_weapon"))


func _busy() -> bool:
	return bool(player.call("weapon_busy"))


func _arrows() -> int:
	return (ARROW_SCRIPT._active as Array).size()


func _charging() -> bool:
	return bool(bow.call("is_charging"))


func _attacking() -> bool:
	return bool(sword.call("is_attacking"))


func _wait_until_idle(max_frames: int) -> int:
	## 等剑的挥砍动画自己结束，返回用了多少帧（超时返回 -1）
	for i in max_frames:
		await process_frame
		if not _attacking():
			return i
	return -1


func _run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var sc: PackedScene = load("res://scenes/main.tscn")
	var w := sc.instantiate()
	w.get_node("Ground").set("seed_value", 88108)
	root.add_child(w)
	await _frames(30)
	player = w.get_node("Player")
	bow = w.get_node("Player/Camera3D/Bow")
	sword = w.get_node("Player/Camera3D/Sword")
	bow.process_mode = Node.PROCESS_MODE_DISABLED      # 计时全部手动推进

	chk(bool(player.get("_has")[0]) and bool(player.get("_has")[1]), "两把武器都已装备（C 才有得切）")

	# ---- 1. 剑：真实挥砍动画期间锁住 C ----
	player.call("set_current_weapon", 0)
	await _frames(2)
	chk(_weapon() == 0 and not _busy(), "剑在手且不忙（基线）")
	sword.call("attack")
	chk(_attacking(), "attack() 后进入挥砍动画")
	chk(_busy(), "挥砍期间 weapon_busy() 为真")
	var blocked := true
	for _i in 4:
		_key(true, KEY_C)
		_key(false, KEY_C)
		blocked = blocked and _weapon() == 0
	chk(blocked, "挥砍动画期间连按 4 次 C 都切不动（仍在剑）")
	var waited: int = await _wait_until_idle(300)
	chk(waited >= 0, "挥砍动画会自己结束（%d 帧后 _attacking 复位）" % waited)
	chk(not _busy(), "动画结束后 weapon_busy() 复位")
	_key(true, KEY_C)
	_key(false, KEY_C)
	chk(_weapon() == 1, "动画结束后 C 恢复可用（切到弓）")

	# ---- 2. 弓：按住 X 蓄力期间锁住 C，且蓄力不断、松手照常射 ----
	var n0 := _arrows()
	_key(true)
	chk(_charging() and _busy(), "按住 X 蓄力中 → weapon_busy() 为真")
	_tick(5)
	var mid := float(bow.get("_charge"))
	_key(true, KEY_C)
	_key(false, KEY_C)
	chk(_weapon() == 1, "蓄力期间按 C 切不动（仍在弓）")
	chk(_charging(), "按 C 不会把蓄力打断")
	chk(absf(float(bow.get("_charge")) - mid) < 0.0001, "按 C 也不会把蓄力清零（仍是 %.2f 秒）" % mid)
	_tick(15)
	chk(float(bow.call("charge_ratio")) > 0.99, "蓄力继续累加到满（实测 %.0f%%）" % [float(bow.call("charge_ratio")) * 100.0])
	_key(false)
	chk(not _charging() and not _busy(), "松手撒放后解除上锁")
	chk(_arrows() == n0 + 1, "这一轮确实射出了箭（%d → %d）" % [n0, _arrows()])
	_key(true, KEY_C)
	_key(false, KEY_C)
	chk(_weapon() == 0, "撒放后 C 立刻可用（切回剑）")

	# ---- 3. 弓：按住左键蓄力同样锁 C ----
	player.call("set_current_weapon", 1)
	await _frames(2)
	bow.set("_cooldown", 0.0)
	_lmb(true)
	chk(_charging() and _busy(), "按住左键蓄力中同样上锁")
	_key(true, KEY_C)
	_key(false, KEY_C)
	chk(_weapon() == 1, "左键蓄力期间按 C 切不动")
	_lmb(false)
	bow.set("_cooldown", 0.0)
	chk(not _busy(), "左键松手后解锁")

	# ---- 4. weapon_busy 只认手上这把 ----
	player.call("set_current_weapon", 0)
	await _frames(2)
	bow.set("_charging", true)                       # 让不在手上的弓"假装"在蓄力
	sword.set("_attacking", false)
	chk(not _busy(), "弓偷偷蓄力但手上是剑 → 不拦 C（只认手上这把）")
	sword.set("_attacking", true)
	chk(_busy(), "剑置忙 → 上锁")
	sword.set("_attacking", false)
	bow.set("_charging", false)
	bow.set("_charge", 0.0)

	# ---- 5. 读档不受锁限制 ----
	sword.set("_attacking", true)
	player.call("set_current_weapon", 1)
	await _frames(2)
	chk(_weapon() == 1, "忙碌中 set_current_weapon 仍能切（读档无条件生效）")
	sword.set("_attacking", false)

	_done()


func _done() -> void:
	print("\n== 切换武器上锁自检结果：%d 项失败 ==" % fails.size())
	for f in fails:
		print("  - " + f)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
