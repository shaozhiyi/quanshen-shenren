extends RefCounted
## BOSS 占位外观：纯程序化低模，用于「名册里配了 placeholder 但真模型还没到位」的联调阶段。
## 一旦 assets/models/ 下放进对应的 .glb，boss.gd 会自动优先用真模型，这里的代码就只是兜底。
## 约定（与 boss.gd 一致）：原点在地面中心、车头朝 +Z、单位米。
##
## 造型对标用户给的参考图：橙色 8×4 自卸重卡（大运重卡那一类）——高顶驾驶室 + 黑色中网、
## 带竖向加强筋的自卸斗、侧面竖排白字「大运重卡」、前双转向桥 + 后双驱动桥共四轴八轮。
## 面数：约 90 个 BoxMesh/CylinderMesh 图元、几千三角形，MX250 上毫无压力。
## 轮子挂在名为 "Wheels" 的节点下，boss.gd 会按速度让它们滚动。


static func _mat(col: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	return mi


static func _cyl(r: float, h: float, mat: Material, steps := 20) -> MeshInstance3D:
	## 圆柱：默认轴沿 Y；调用方自己旋转到需要朝向
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = steps
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	return mi


static func build_truck(tint := Color(1, 1, 1)) -> Node3D:
	## 橙色 8×4 自卸重卡：长 10.6 · 宽 3.0 · 高 3.8 米，车头朝 +Z
	var root := Node3D.new()
	root.name = "TruckPlaceholder"

	var orange := _mat(Color(0.760, 0.085, 0.020) * tint, 0.42, 0.10)      # 主色（参考图那种橙红）
	var orange_dark := _mat(Color(0.560, 0.055, 0.015) * tint, 0.50, 0.10)  # 竖筋/暗面
	var black := _mat(Color(0.075, 0.072, 0.070), 0.75)
	var gray := _mat(Color(0.26, 0.26, 0.28), 0.8)
	var steel := _mat(Color(0.66, 0.67, 0.70), 0.32, 0.85)
	var rubber := _mat(Color(0.055, 0.055, 0.060), 0.95)
	var rim := _mat(Color(0.58, 0.56, 0.52), 0.55, 0.5)
	var glass := _mat(Color(0.10, 0.16, 0.24), 0.12, 0.45)
	var lamp := _mat(Color(1.0, 0.95, 0.72), 0.25)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.93, 0.62)
	lamp.emission_energy_multiplier = 1.8

	# ---- 底盘大梁（纵梁 + 横梁）----
	root.add_child(_box(Vector3(0.26, 0.34, 9.6), Vector3(-0.95, 1.12, -0.1), black))
	root.add_child(_box(Vector3(0.26, 0.34, 9.6), Vector3(0.95, 1.12, -0.1), black))
	for i in 5:
		root.add_child(_box(Vector3(2.0, 0.16, 0.22), Vector3(0.0, 1.10, 3.4 - float(i) * 1.9), black))

	# ---- 高顶驾驶室 ----
	root.add_child(_box(Vector3(2.62, 2.05, 2.35), Vector3(0.0, 2.30, 4.15), orange))       # 主体
	root.add_child(_box(Vector3(2.62, 0.42, 2.30), Vector3(0.0, 3.52, 4.15), orange))       # 高顶
	root.add_child(_box(Vector3(2.66, 0.14, 2.34), Vector3(0.0, 3.76, 4.15), orange_dark))  # 顶盖
	root.add_child(_box(Vector3(2.30, 0.96, 0.10), Vector3(0.0, 2.98, 5.30), glass))        # 前挡玻璃
	root.add_child(_box(Vector3(2.66, 0.26, 0.16), Vector3(0.0, 3.56, 5.30), orange_dark))  # 遮阳板
	root.add_child(_box(Vector3(0.98, 0.72, 0.08), Vector3(-0.86, 2.86, 2.99), glass))      # 左门窗
	root.add_child(_box(Vector3(0.98, 0.72, 0.08), Vector3(0.86, 2.86, 2.99), glass))       # 右门窗
	root.add_child(_box(Vector3(0.34, 0.72, 0.08), Vector3(-1.32, 2.86, 2.99), glass))      # 左三角窗
	root.add_child(_box(Vector3(0.34, 0.72, 0.08), Vector3(1.32, 2.86, 2.99), glass))       # 右三角窗

	# ---- 前脸：中网 + 镀铬横条 + 车标 + 大灯 + 保险杠 ----
	root.add_child(_box(Vector3(2.10, 0.86, 0.14), Vector3(0.0, 2.02, 5.34), black))
	for i in 3:
		root.add_child(_box(Vector3(2.02, 0.10, 0.08), Vector3(0.0, 1.76 + float(i) * 0.26, 5.40), steel))
	var logo := _cyl(0.20, 0.10, steel, 18)
	logo.rotation_degrees = Vector3(90, 0, 0)
	logo.position = Vector3(0.0, 2.06, 5.44)
	root.add_child(logo)
	for s in [-1, 1]:
		root.add_child(_box(Vector3(0.42, 0.30, 0.12), Vector3(float(s) * 1.10, 1.52, 5.38), lamp))
		root.add_child(_box(Vector3(0.42, 0.24, 0.12), Vector3(float(s) * 1.10, 1.20, 5.38), lamp))
	root.add_child(_box(Vector3(2.86, 0.44, 0.40), Vector3(0.0, 1.02, 5.30), gray))
	root.add_child(_box(Vector3(1.10, 0.16, 0.30), Vector3(0.0, 0.72, 5.28), black))

	# ---- 后视镜（长支架 + 镜壳）----
	for s in [-1, 1]:
		root.add_child(_box(Vector3(0.10, 0.10, 0.44), Vector3(float(s) * 1.46, 3.20, 4.86), black))
		root.add_child(_box(Vector3(0.12, 0.62, 0.20), Vector3(float(s) * 1.52, 3.16, 5.06), black))

	# ---- 登车踏步 ----
	root.add_child(_box(Vector3(0.42, 0.10, 0.60), Vector3(-1.36, 1.42, 3.30), steel))
	root.add_child(_box(Vector3(0.42, 0.10, 0.60), Vector3(-1.36, 1.02, 3.30), steel))

	# ---- 油箱 / 储气筒 / 排气竖管 ----
	var tank := _cyl(0.36, 1.55, steel, 18)
	tank.rotation_degrees = Vector3(90, 0, 0)
	tank.position = Vector3(1.32, 1.45, 2.30)
	root.add_child(tank)
	var tank2 := _cyl(0.36, 1.55, steel, 18)
	tank2.rotation_degrees = Vector3(90, 0, 0)
	tank2.position = Vector3(-1.32, 1.45, 1.60)
	root.add_child(tank2)
	for i in 2:
		var air := _cyl(0.16, 1.05, gray, 14)
		air.rotation_degrees = Vector3(90, 0, 0)
		air.position = Vector3(-1.30, 1.62, 0.30 - float(i) * 1.15)
		root.add_child(air)
	var stack := _cyl(0.075, 1.00, steel, 12)
	stack.position = Vector3(1.24, 2.55, 2.86)
	root.add_child(stack)

	# ---- 自卸斗：底板 + 侧壁 + 前挡板 + 尾板 + 上下横梁 + 竖向加强筋 ----
	root.add_child(_box(Vector3(2.86, 0.20, 6.90), Vector3(0.0, 1.80, -1.55), orange_dark))
	root.add_child(_box(Vector3(0.12, 1.55, 6.90), Vector3(-1.40, 2.66, -1.55), orange))
	root.add_child(_box(Vector3(0.12, 1.55, 6.90), Vector3(1.40, 2.66, -1.55), orange))
	root.add_child(_box(Vector3(2.86, 1.75, 0.14), Vector3(0.0, 2.72, 1.86), orange))
	root.add_child(_box(Vector3(2.86, 0.30, 0.16), Vector3(0.0, 3.72, 1.86), orange_dark))
	root.add_child(_box(Vector3(2.86, 1.55, 0.14), Vector3(0.0, 2.66, -5.00), orange_dark))
	for s in [-1, 1]:
		root.add_child(_box(Vector3(0.10, 0.13, 6.94), Vector3(float(s) * 1.44, 3.46, -1.55), orange_dark))
		root.add_child(_box(Vector3(0.10, 0.13, 6.94), Vector3(float(s) * 1.44, 1.90, -1.55), orange_dark))
		for i in 9:
			var z := 1.45 - float(i) * 0.72
			root.add_child(_box(Vector3(0.11, 1.46, 0.20), Vector3(float(s) * 1.47, 2.68, z), orange_dark))
	for s in [-1, 1]:
		var hinge := _cyl(0.11, 0.34, gray, 12)
		hinge.rotation_degrees = Vector3(0, 0, 90)
		hinge.position = Vector3(float(s) * 1.05, 3.44, -5.06)
		root.add_child(hinge)

	# ---- 侧面竖排白字「大运重卡」（贴图缺失时自动跳过）----
	if ResourceLoader.exists("res://assets/models/truck_lettering.png"):
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.cull_mode = BaseMaterial3D.CULL_DISABLED
		lm.albedo_texture = load("res://assets/models/truck_lettering.png")
		for s in [-1, 1]:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.55, 1.46)
			q.mesh = qm
			q.material_override = lm
			q.position = Vector3(float(s) * 1.485, 2.66, 0.55)
			q.rotation_degrees = Vector3(0.0, 90.0 * float(s), 0.0)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(q)

	# ---- 后桥挡泥板 / 侧面防护栏 / 挡泥皮 ----
	root.add_child(_box(Vector3(2.90, 0.12, 2.10), Vector3(0.0, 1.92, -3.55), black))
	for s in [-1, 1]:
		root.add_child(_box(Vector3(0.10, 0.10, 2.30), Vector3(float(s) * 1.45, 0.95, -3.40), gray))
		root.add_child(_box(Vector3(0.30, 0.90, 0.06), Vector3(float(s) * 1.35, 0.62, -5.06), black))
		root.add_child(_box(Vector3(0.34, 0.10, 1.50), Vector3(float(s) * 1.42, 1.68, 3.34), black))

	# ---- 四轴八轮（前双转向桥 + 后双驱动桥），挂在 "Wheels" 下供滚动 ----
	var wheels := Node3D.new()
	wheels.name = "Wheels"
	wheels.set_meta("radius", 0.78)
	root.add_child(wheels)
	for z in [3.95, 2.72, -2.90, -4.18]:
		for x in [-1.34, 1.34]:
			var pivot := Node3D.new()
			pivot.position = Vector3(x, 0.78, z)
			var tire := _cyl(0.78, 0.55, rubber, 26)
			tire.rotation_degrees = Vector3(90, 0, 0)     # 轴转到 X 方向，滚动即绕局部 X
			pivot.add_child(tire)
			var drum := _cyl(0.40, 0.60, rim, 18)
			drum.rotation_degrees = Vector3(90, 0, 0)
			pivot.add_child(drum)
			var hub := _cyl(0.14, 0.66, steel, 12)
			hub.rotation_degrees = Vector3(90, 0, 0)
			pivot.add_child(hub)
			wheels.add_child(pivot)
	return root
