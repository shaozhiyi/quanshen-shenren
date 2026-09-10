extends SceneTree
## 无敌显示自检：血条数字应显示"永久"（时长仍 10 秒），结束后恢复 数字/100
const OUT := "user://shots/"
var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	print(("  ok   | " if cond else "  FAIL | ") + msg)
	if not cond:
		fails.append(msg)


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var w := scene.instantiate()
	w.get_node("Ground").set("seed_value", 31415)
	root.add_child(w)
	await _frames(40)

	var player := w.get_node("Player")
	var hud := w.get_node("HUD")
	var bar: Control = hud.get("_bar")
	player.hp = 71.0
	hud.call("_on_hp_changed", 71.0, 100.0)
	await _frames(5)
	chk(String(bar.style.label_format) == "{value}/{max}", "常态：血条显示 数字/100")
	root.get_texture().get_image().save_png(OUT + "hpbar_normal.png")

	player.call("gain_invincibility", 10.0)
	await _frames(10)
	chk(String(bar.style.label_format) == "永久", "无敌中：血条数字变成『永久』")
	chk(bool(player.call("is_invincible")), "无敌状态确实生效")
	chk(hud.get("_inv_label") == null, "旧的『无敌 X.Xs』标签已移除")
	root.get_texture().get_image().save_png(OUT + "hpbar_permanent.png")

	# 时长仍是 10 秒：跑到 9.5 秒时应仍无敌，之后恢复
	player.set("_invincible_t", 9.5)
	await _frames(6)
	chk(bool(player.call("is_invincible")), "持续时长仍按 10 秒计（9.5s 时还无敌）")
	player.set("_invincible_t", 0.05)
	await _frames(12)
	chk(not bool(player.call("is_invincible")), "10 秒后解除无敌")
	chk(abs(player.hp - 100.0) < 1e-6, "解除时恢复满血（hp=%.1f）" % player.hp)
	chk(String(bar.style.label_format) == "{value}/{max}", "解除后血条数字恢复 数字/100")
	root.get_texture().get_image().save_png(OUT + "hpbar_after.png")

	print("\n== 结果：%d 项失败 ==" % fails.size())
	quit(0 if fails.is_empty() else 1)
