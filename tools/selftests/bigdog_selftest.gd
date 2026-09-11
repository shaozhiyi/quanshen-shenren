extends SceneTree
## 「大狗叫」模型入库自检：确认 Blender 手搓的 bigdog.glb 在 Godot 里
## 导入正常（网格/材质/尺寸/朝向），并出一张引擎内实拍图供肉眼核对。
## 必须窗口模式跑（无头时 root.get_texture() 为 null，存不了 PNG）。
##   用法：Godot --path . --scene 无关，本脚本自建场景：
##     Godot_console.exe --path . --script res://tools/selftests/bigdog_selftest.gd
const OUT_DIR := "user://shots/"
const GLB := "res://assets/models/bigdog.glb"
## 建模脚本里量出来的原始尺寸（米）：宽 0.38 × 高 0.60 × 长 1.02
const WANT := {"w": 0.38, "h": 0.60, "l": 1.02}
const MAT_COUNT := 10
var fails: Array[String] = []


func chk(cond: bool, msg: String) -> void:
	print(("  ok   | " if cond else "  FAIL | ") + msg)
	if not cond:
		fails.append(msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	chk(ResourceLoader.exists(GLB), "GLB 资源存在：" + GLB)
	if not ResourceLoader.exists(GLB):
		_end()
		return
	var scene: PackedScene = load(GLB)
	chk(scene != null, "GLB 能被 load() 成 PackedScene")

	# 自建一个展示场景：狗 + 三点光 + 相机（相机放在 -Z 前方，正对狗脸）
	var world := Node3D.new()
	world.name = "DogShowcase"
	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.55, 0.58, 0.62)
	env.environment = we
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 28, 0)
	sun.light_energy = 1.2
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20, -140, 0)
	fill.light_energy = 0.4
	world.add_child(fill)
	var dog: Node = scene.instantiate()
	world.add_child(dog)
	var cam := Camera3D.new()
	cam.position = Vector3(0.42, 0.46, -1.35)
	cam.fov = 45.0
	world.add_child(cam)
	root.add_child(world)
	cam.look_at_from_position(Vector3(0.42, 0.46, -1.35), Vector3(0, 0.34, 0), Vector3.UP)
	await _frames(30)

	# 网格与材质
	var meshes: Array[MeshInstance3D] = []
	for n in _walk(dog):
		if n is MeshInstance3D:
			meshes.append(n)
	chk(not meshes.is_empty(), "至少有一个 MeshInstance3D（实得 %d）" % meshes.size())
	var mat_names: Array[String] = []
	var tris := 0
	for mi in meshes:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m != null:
				mat_names.append(String(m.resource_name))
			var arrays := mi.mesh.surface_get_arrays(i)
			if arrays != null:
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				tris += (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
	print("       材质：%s" % ", ".join(mat_names))
	print("       三角面：%d" % tris)
	chk(mat_names.size() >= MAT_COUNT, "材质槽数量 %d ≥ %d（毛/口鼻/牙/舌/眼等分层没丢）" % [mat_names.size(), MAT_COUNT])
	chk(tris > 6000 and tris < 30000, "面数在武器可接受区间（%d）" % tris)

	# 尺寸与朝向：Godot 里 X=宽、Y=高、Z=长；狗头应朝 -Z
	var aabb := _world_aabb(dog)
	var s := aabb.size
	print("       包围盒 size=%.3f %.3f %.3f  pos=%.3f %.3f %.3f" % [s.x, s.y, s.z, aabb.position.x, aabb.position.y, aabb.position.z])
	chk(abs(s.x - WANT.w) < 0.05, "宽度 ≈ %.2fm（实得 %.3f）" % [WANT.w, s.x])
	chk(abs(s.y - WANT.h) < 0.05, "高度 ≈ %.2fm（实得 %.3f）" % [WANT.h, s.y])
	chk(abs(s.z - WANT.l) < 0.05, "长度 ≈ %.2fm（实得 %.3f）" % [WANT.l, s.z])
	# 朝向：按材质找鼻头和牙齿，它们必须在 -Z（Godot 正前方）一侧。
	# 只看包围盒偏移是没用的——glTF 轴换算把狗翻成屁股朝前时，包围盒照样对称。
	var nose_z := _mat_center_z(dog, "dog_nose")
	var tooth_z := _mat_center_z(dog, "dog_tooth")
	print("       鼻头中心 z=%.3f  牙齿中心 z=%.3f" % [nose_z, tooth_z])
	chk(nose_z < -0.25, "鼻头在 -Z 前方（z=%.3f，狗头朝向正确）" % nose_z)
	chk(tooth_z < -0.15, "牙齿也在 -Z 前方（z=%.3f）" % tooth_z)
	chk(abs(aabb.position.y) < 0.05, "原点在四脚着地的地面（min y=%.3f）" % aabb.position.y)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var png := OUT_DIR + "bigdog_showcase.png"
	var err := root.get_texture().get_image().save_png(png)
	chk(err == OK, "引擎内截图保存成功（err=%d）" % err)
	if err == OK:
		var f := FileAccess.open(png, FileAccess.READ)
		var sz := f.get_length() if f != null else 0
		if f != null:
			f.close()
		chk(sz > 20000, "截图非空（%d 字节）" % sz)
		print("       截图：%s" % ProjectSettings.globalize_path(png))
	# 再存一张正脸特写（先把窗口设成正方形，免得狗头被裁掉）
	root.size = Vector2i(760, 760)
	await _frames(6)
	cam.position = Vector3(0.16, 0.44, -0.72)
	cam.look_at_from_position(cam.position, Vector3(0, 0.40, -0.20), Vector3.UP)
	await _frames(10)
	var png2 := OUT_DIR + "bigdog_face.png"
	chk(root.get_texture().get_image().save_png(png2) == OK, "正脸特写截图保存成功")
	print("       截图：%s" % ProjectSettings.globalize_path(png2))
	_end()


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


## 按材质名取那一面顶点的平均世界坐标 z（鼻头/牙齿在前后哪一侧就看它）。
## 不能用 mesh.get_aabb()——ArrayMesh 那个是整网格的，分不到单个 surface。
func _mat_center_z(n: Node, mat_name: String) -> float:
	for c in _walk(n):
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m == null or String(m.resource_name) != mat_name:
				continue
			var arrays: Array = mi.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var avg := Vector3.ZERO
			for v in verts:
				avg += v
			avg /= float(verts.size())
			return (mi.global_transform * avg).z
	return NAN


func _world_aabb(n: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for c in _walk(n):
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			var a := mi.global_transform * mi.mesh.get_aabb()
			if first:
				total = a
				first = false
			else:
				total = total.merge(a)
	return total


func _end() -> void:
	print("\n== 大狗模型自检：%d 项失败 ==" % fails.size())
	for m in fails:
		print("  失败：" + m)
	quit(0 if fails.is_empty() else 1)


func _initialize() -> void:
	_run()
