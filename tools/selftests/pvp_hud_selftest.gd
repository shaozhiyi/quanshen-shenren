extends SceneTree
## PVP HUD 血条/蓝条自检：HealthBarX 是百分比条，量程必须恒 100、传百分比。
## 验证 700/700 满填充、100/200 半填充，并截屏肉眼复核。

const SHOT := "user://pvp_hud_bars.png"


class Dummy extends Node:
	signal hp_changed(v: float, mx: float)
	signal mp_changed(v: float, mx: float)
	signal invincibility_changed(active: bool, dur: float)
	var hp := 700.0
	var max_hp := 700.0
	var mp := 100.0
	var max_mp := 200.0


func _idle(n: int) -> void:
	for _i in n:
		await physics_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	var fails := 0
	var hud: CanvasLayer = (load("res://scripts/pvp/pvp_hud.gd") as GDScript).new()
	root.add_child(hud)
	await _idle(5)
	var dummy := Dummy.new()
	hud.bind(dummy)
	await _idle(5)

	var hp_bar: Control = hud._hp_bar
	var mp_bar: Control = hud._mp_bar
	var chk := func(ok: bool, tag: String) -> void:
		if ok:
			print("PASS ", tag)
		else:
			fails += 1
			print("FAIL ", tag)

	chk.call(absf(float(hp_bar.get_value()) - 100.0) < 0.01, "满血填充=100%（实际 %s）" % str(hp_bar.get_value()))
	chk.call(absf(float(mp_bar.get_value()) - 50.0) < 0.01, "半蓝填充=50%%（实际 %s）" % str(mp_bar.get_value()))

	# 掉血后按比例回落
	dummy.hp = 350.0
	hud._on_hp(350.0, 700.0)
	chk.call(absf(float(hp_bar.get_value()) - 50.0) < 0.01, "半血填充=50%%（实际 %s）" % str(hp_bar.get_value()))

	await _idle(5)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(SHOT)
	print("SHOT:", SHOT)
	print("RESULT:", "OK" if fails == 0 else "BAD")
	quit(0 if fails == 0 else 1)
