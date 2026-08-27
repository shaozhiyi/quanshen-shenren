extends Node3D
## 地表杂物：小石子散布，丰富地表细节，自动贴合地形起伏。

@export var rock_count := 700
@export var area_half := 120.0

const ROCK_SHADER := preload("res://shaders/rock.gdshader")


func _ready() -> void:
	if get_child_count() == 0:
		_build_details()


func _build_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_build_rocks(rng)


func _ground_height(x: float, z: float) -> float:
	var ground := get_node_or_null("../Ground")
	if ground != null and ground.has_method("height_at"):
		return ground.height_at(x, z)
	return 0.0


func _build_rocks(rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _make_rock_mesh()
	mm.instance_count = rock_count
	for i in rock_count:
		var t := Transform3D.IDENTITY
		var x := rng.randf_range(-area_half, area_half)
		var z := rng.randf_range(-area_half, area_half)
		t.origin = Vector3(x, _ground_height(x, z) - 0.02, z)
		t.basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		t = t.scaled(Vector3(
			rng.randf_range(0.05, 0.16),
			rng.randf_range(0.03, 0.09),
			rng.randf_range(0.05, 0.16)
		))
		mm.set_instance_transform(i, t)
		mm.set_instance_custom_data(i, Color(rng.randf(), 0.0, 0.0, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _make_rock_mesh() -> Mesh:
	# 低模石头：细分较少的球体压扁，再叠加 shader 微变形
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 4
	var mat := ShaderMaterial.new()
	mat.shader = ROCK_SHADER
	sphere.material = mat
	return sphere
