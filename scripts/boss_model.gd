extends RefCounted
## BOSS 占位外观：纯程序化低模，用于「名册里配了 placeholder 但真模型还没到位」的联调阶段。
## 一旦 assets/models/ 下放进对应的 .glb，boss.gd 会自动优先用真模型，这里的代码就只是兜底。
## 约定（与 boss.gd 一致）：原点在地面中心、车头朝 +Z、单位米。
##
## 面数控制：全部用 BoxMesh / CylinderMesh 拼，重卡约 40 个图元、几千三角形，
## MX250 上毫无压力；轮子单独挂在名为 "Wheels" 的节点下，boss.gd 会按速度让它们滚动。


static func _mat(col: Color, rough := 0.65, metal := 0.0) -> StandardMaterial3D:
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
	## 红色栏板重卡（三轴，长 9.2 · 宽 2.6 · 高 3.3 米），车头朝 +Z
	var root := Node3D.new()
	root.name = "TruckPlaceholder"

	var red := _mat(Color(0.74, 0.11, 0.09) * tint, 0.45, 0.15)      # 车身红
	var red_dark := _mat(Color(0.52, 0.08, 0.07) * tint, 0.55, 0.10)  # 栏板/暗面
	var gray := _mat(Color(0.24, 0.25, 0.27), 0.8)                    # 底盘
	var steel := _mat(Color(0.62, 0.64, 0.68), 0.35, 0.85)            # 镀铬/保险杠
	var rubber := _mat(Color(0.09, 0.09, 0.10), 0.95)                 # 轮胎
	var hub := _mat(Color(0.72, 0.70, 0.62), 0.5, 0.6)                # 轮毂
	var glass := _mat(Color(0.16, 0.24, 0.34, 1.0), 0.15, 0.4)        # 车窗
	var lamp := _mat(Color(1.0, 0.92, 0.62), 0.3)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.9, 0.55)
	lamp.emission_energy_multiplier = 2.2
	var cargo := _mat(Color(0.66, 0.55, 0.36), 0.9)                   # 货物

	# ---- 底盘大梁 ----
	root.add_child(_box(Vector3(0.9, 0.28, 8.4), Vector3(0, 0.78, -0.2), gray))
	root.add_child(_box(Vector3(2.3, 0.16, 1.6), Vector3(0, 0.72, 3.0), gray))

	# ---- 驾驶室 ----
	root.add_child(_box(Vector3(2.5, 1.85, 2.3), Vector3(0, 1.83, 3.25), red))       # 主体
	root.add_child(_box(Vector3(2.34, 0.62, 0.1), Vector3(0, 2.36, 4.42), glass))    # 前挡
	root.add_child(_box(Vector3(0.9, 0.55, 0.08), Vector3(-0.78, 2.3, 2.12), glass)) # 侧窗（左）
	root.add_child(_box(Vector3(0.9, 0.55, 0.08), Vector3(0.78, 2.3, 2.12), glass))  # 侧窗（右）
	root.add_child(_box(Vector3(2.28, 0.52, 0.14), Vector3(0, 1.32, 4.44), steel))   # 中网
	root.add_child(_box(Vector3(2.6, 0.34, 0.3), Vector3(0, 0.98, 4.42), steel))     # 前保险杠
	root.add_child(_box(Vector3(0.44, 0.24, 0.1), Vector3(-0.92, 1.66, 4.46), lamp)) # 左大灯
	root.add_child(_box(Vector3(0.44, 0.24, 0.1), Vector3(0.92, 1.66, 4.46), lamp))  # 右大灯
	root.add_child(_box(Vector3(0.16, 0.5, 0.34), Vector3(-1.36, 2.34, 4.0), gray))  # 左后视镜
	root.add_child(_box(Vector3(0.16, 0.5, 0.34), Vector3(1.36, 2.34, 4.0), gray))   # 右后视镜
	root.add_child(_box(Vector3(2.16, 0.14, 1.9), Vector3(0, 2.82, 3.3), red_dark))  # 顶棚

	# ---- 排气竖管 ----
	var pipe_l := _cyl(0.07, 1.5, steel, 12)
	pipe_l.position = Vector3(-1.2, 1.9, 2.05)
	root.add_child(pipe_l)
	var pipe_r := _cyl(0.07, 1.5, steel, 12)
	pipe_r.position = Vector3(1.2, 1.9, 2.05)
	root.add_child(pipe_r)

	# ---- 货台 + 栏板 ----
	root.add_child(_box(Vector3(2.5, 0.22, 6.2), Vector3(0, 1.12, -1.55), red_dark))  # 货台
	root.add_child(_box(Vector3(0.1, 1.15, 6.2), Vector3(-1.24, 1.8, -1.55), red))    # 左栏板
	root.add_child(_box(Vector3(0.1, 1.15, 6.2), Vector3(1.24, 1.8, -1.55), red))     # 右栏板
	root.add_child(_box(Vector3(2.5, 1.15, 0.1), Vector3(0, 1.8, 1.5), red))          # 前横梁
	root.add_child(_box(Vector3(2.5, 1.15, 0.1), Vector3(0, 1.8, -4.6), red))         # 尾板
	for i in 5:
		var z := 1.1 - float(i) * 1.4
		root.add_child(_box(Vector3(0.16, 1.25, 0.16), Vector3(-1.26, 1.82, z), red_dark))
		root.add_child(_box(Vector3(0.16, 1.25, 0.16), Vector3(1.26, 1.82, z), red_dark))
	# 货物（高出栏板一点，看着是"拉满了一车"）
	root.add_child(_box(Vector3(2.2, 0.7, 5.7), Vector3(0, 2.5, -1.6), cargo))
	root.add_child(_box(Vector3(1.5, 0.45, 2.2), Vector3(-0.2, 3.02, -2.6), cargo))

	# ---- 三轴六轮（挂在 "Wheels" 下，boss.gd 按速度让它们滚）----
	var wheels := Node3D.new()
	wheels.name = "Wheels"
	wheels.set_meta("radius", 0.56)
	root.add_child(wheels)
	var axles := [3.15, -2.35, -3.65]
	for z in axles:
		for x in [-1.26, 1.26]:
			var pivot := Node3D.new()
			pivot.position = Vector3(x, 0.56, z)
			var tire := _cyl(0.56, 0.42, rubber, 22)
			tire.rotation_degrees = Vector3(90, 0, 0)     # 轴转到 X 方向，滚动即绕局部 X
			pivot.add_child(tire)
			var drum := _cyl(0.26, 0.46, hub, 14)
			drum.rotation_degrees = Vector3(90, 0, 0)
			pivot.add_child(drum)
			wheels.add_child(pivot)

	# ---- 车底裙板（挡住"看见轮间空隙"的穿帮感）----
	root.add_child(_box(Vector3(2.46, 0.5, 6.1), Vector3(0, 1.05, -1.55), red_dark))
	return root
