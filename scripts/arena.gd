extends Node3D
## BOSS 战斗空间：超平坦纯白地板 + 正常太阳 + 无云天空。
## 平时隐藏；玩家在大地图按 E 进入（player.gd 负责传送与显隐切换）。
## 空间搭建全部程序化生成，不依赖外部素材。

const ARENA_CENTER := Vector3(0.0, 100.0, 0.0)   # 悬空在大地图上方，避免穿模
const FLOOR_SIZE := 800.0                        # 超平坦：大到目视看不到边界
const HALF := FLOOR_SIZE / 2.0

var arena_env: Environment    # 供 player 临时切换大地图 WorldEnvironment 使用

var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D

const DAY_TOP := Color(0.45, 0.63, 0.90)
const NIGHT_TOP := Color(0.02, 0.03, 0.10)
const DAY_HORIZON := Color(0.80, 0.87, 0.96)
const NIGHT_HORIZON := Color(0.08, 0.10, 0.20)
const DAY_GROUND := Color(0.92, 0.92, 0.94)
const NIGHT_GROUND := Color(0.06, 0.07, 0.12)


func _ready() -> void:
	add_to_group("arena")
	position = ARENA_CENTER
	visible = false

	# 无云天空 + 均匀环境光（作为可交换的 Environment 资源，避免多 WorldEnvironment 冲突）
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = DAY_TOP
	psm.sky_horizon_color = DAY_HORIZON
	psm.ground_bottom_color = DAY_GROUND
	psm.ground_horizon_color = DAY_HORIZON
	psm.sun_angle_max = 8.0
	psm.sun_curve = 0.3
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	arena_env = env
	_sky_mat = psm

	# 正常太阳（平行光 + 阴影）
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -35, 0)
	_sun.light_energy = 1.6
	_sun.shadow_enabled = true
	add_child(_sun)

	# 月亮（冷色平行光，夜间渐亮）
	_moon = DirectionalLight3D.new()
	_moon.rotation_degrees = Vector3(-46, 140, 0)
	_moon.light_color = Color(0.62, 0.70, 1.0)
	_moon.light_energy = 0.0
	_moon.shadow_enabled = false
	add_child(_moon)

	# 超平坦白色地板（视觉）
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.97, 0.97, 0.98)
	wmat.roughness = 0.9
	pm.material = wmat
	floor_mi.mesh = pm
	add_child(floor_mi)

	# 碰撞：厚盒（超平坦，无边界墙）
	add_child(_slab(Vector3(0, -0.5, 0), Vector3(FLOOR_SIZE, 1.0, FLOOR_SIZE)))


func set_day_night(night: float) -> void:
	## night=0 白昼 → 1 深夜（攻击期间的日月交替由 boss 按时间轴驱动）
	var n := clampf(night, 0.0, 1.0)
	_sun.light_energy = lerpf(1.6, 0.0, n)
	_sun.rotation_degrees = Vector3(lerpf(-52.0, 24.0, n), -35.0, 0.0)
	_moon.light_energy = lerpf(0.0, 0.55, n)
	_sky_mat.sky_top_color = DAY_TOP.lerp(NIGHT_TOP, n)
	_sky_mat.sky_horizon_color = DAY_HORIZON.lerp(NIGHT_HORIZON, n)
	_sky_mat.ground_bottom_color = DAY_GROUND.lerp(NIGHT_GROUND, n)
	_sky_mat.ground_horizon_color = DAY_HORIZON.lerp(NIGHT_HORIZON, n)
	arena_env.ambient_light_energy = lerpf(1.0, 0.22, n)


func _slab(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var csc := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	csc.shape = box
	csc.position = pos
	body.add_child(csc)
	return body


func floor_y() -> float:
	return ARENA_CENTER.y


func set_active(b: bool) -> void:
	visible = b


func is_active() -> bool:
	return visible


func theme_key() -> String:
	return "white"


func center() -> Vector3:
	return ARENA_CENTER


func bounds_half() -> float:
	return HALF


## 玩家/BOSS 在空间内的落点（国道空间要靠这个把双方摆到同一条车道上）
func player_spawn() -> Vector3:
	return ARENA_CENTER + Vector3(0.0, 1.05, 6.0)


func boss_spawn() -> Vector3:
	return ARENA_CENTER + Vector3(0.0, 0.0, -10.0)


func inside(p: Vector3) -> bool:
	return absf(p.x - ARENA_CENTER.x) < HALF and absf(p.z - ARENA_CENTER.z) < HALF
