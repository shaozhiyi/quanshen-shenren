extends MeshInstance3D
## 天空穹顶：真实 3D 球体 + HDRI 照片纹理（unshaded），绕开 PanoramaSkyMaterial 导致地形不渲染的问题。
@export var dome_radius := 450.0
@export var hdr_path := "res://assets/sky/kloofendal_48d_partly_cloudy.hdr"
const SKY_DOME_SHADER := preload("res://shaders/sky_dome.gdshader")
func _ready() -> void:
	if mesh == null:
		_build_dome()
func _build_dome() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = dome_radius
	sphere.height = dome_radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 48
	var mat := ShaderMaterial.new()
	mat.shader = SKY_DOME_SHADER
	mat.set_shader_parameter("sky_tex", load(hdr_path))
	sphere.material = mat
	mesh = sphere
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
