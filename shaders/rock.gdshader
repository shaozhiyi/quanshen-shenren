shader_type spatial;

uniform vec3 rock_color : source_color = vec3(0.52, 0.50, 0.45);
uniform float rock_roughness : hint_range(0.0, 1.0) = 0.9;

varying float v_seed;

void vertex() {
	v_seed = INSTANCE_CUSTOM.x;
	// 轻微随机变形，避免每颗石头都一模一样
	VERTEX.x *= mix(0.92, 1.08, fract(v_seed * 7.13));
	VERTEX.z *= mix(0.92, 1.08, fract(v_seed * 3.71));
}

void fragment() {
	ALBEDO = rock_color * (0.78 + 0.44 * v_seed);
	ROUGHNESS = rock_roughness;
}
