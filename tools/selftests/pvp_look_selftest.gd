extends SceneTree
## 远程玩家武器外观自检：摆一个"别人"（非权威 PvpPlayer），依次点亮剑/弓/法杖，
## 各截一张图肉眼复核比例与朝向。跑法：godot --path 项目 --script 本文件

const DIR := "user://shots"


func _idle(n: int) -> void:
	for _i in n:
		await physics_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.72)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	world.add_child(sun)

	var foe: CharacterBody3D = (load("res://scripts/pvp/pvp_player.gd") as GDScript).new()
	foe.setup(2, "玩家2", Vector3.ZERO)   # 权威=2，本机 unique id=1 → 这是"别人"
	world.add_child(foe)
	await _idle(5)

	var cam := Camera3D.new()
	# 前右侧 3/4 视角：能同时看到脸的朝向与手里的武器
	cam.position = Vector3(2.0, 1.5, -2.0)
	cam.current = true
	root.add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	await _idle(5)

	var cases := {1: "sword", 2: "bow", 3: "staff"}
	for w in cases:
		foe.call("_apply_remote_state", int(w), 100 + int(w), 0, 0.0)
		await _idle(4)
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/pvp_look_%s.png" % [DIR, String(cases[w])]
		img.save_png(path)
		print("shot ", path)
	# 动作帧：挥砍中（包络峰值附近）
	foe.call("_apply_remote_state", 1, 200, 1, 0.0)
	foe.set("_rem_t", 0.17)
	await _idle(2)
	root.get_viewport().get_texture().get_image().save_png(DIR + "/pvp_look_slash.png")
	print("shot ", DIR + "/pvp_look_slash.png")
	print("DONE")
	quit(0)
