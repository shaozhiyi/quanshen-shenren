shader_type spatial;
uniform vec3 color_a : source_color = vec3(0.30, 0.54, 0.22);
uniform vec3 color_b : source_color = vec3(0.44, 0.69, 0.32);
uniform vec3 color_dry : source_color = vec3(0.62, 0.56, 0.28);
uniform vec3 color_soil : source_color = vec3(0.38, 0.30, 0.19);
uniform float patch_scale = 0.10;
uniform float detail_scale = 5.0;
uniform float repeat = 40.0;
// 照片级草地纹理（Poly Haven leafy_grass，CC0）
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_repeat = 60.0;
// 地形起伏参数（与 terrain.gd 的 height_at 完全一致，保证草/碰撞对齐）
uniform float height_amp : hint_range(0.0, 20.0) = 13.0;
uniform float frequency = 0.009;
uniform float height_step = 3.125;
// 噪声域偏移：由 terrain.gd 按随机种子下发，换种子即换一片山脉；默认值=原始固定地形
uniform vec2 noise_off0 = vec2(0.0, 0.0);
uniform vec2 noise_off2 = vec2(17.0, 3.0);
uniform vec2 noise_off3 = vec2(7.0, 11.0);
varying float v_world_y;
varying vec2 v_world_xz;
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p = vec2(p.x * 0.8 + p.y * 0.6, -0.6 * p.x + 0.8 * p.y) * 2.02;
		amp *= 0.5;
	}
	return v;
}
// 轻量 3 倍频版本：用于 fragment 里的大尺度色斑/云影（视觉几乎无差，省 ~40% 噪声计算）
float fbm3(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise(p);
		p = vec2(p.x * 0.8 + p.y * 0.6, -0.6 * p.x + 0.8 * p.y) * 2.02;
		amp *= 0.5;
	}
	return v;
}
float terrain_height(vec2 p) {
	float n = fbm(p * frequency + noise_off0);
	float n2 = fbm(p * frequency * 4.0 + noise_off2);
	float n3 = fbm(p * frequency * 6.0 + noise_off3);
	return (n * 0.75 + n2 * 0.25 + n3 * 0.12) * height_amp * 2.0 - height_amp;
}
void vertex() {
	// 顶点位移生成起伏地形（与 CPU 端 height_at 同公式），并重算法线
	vec2 p = VERTEX.xz;
	float h = terrain_height(p);
	float hx = terrain_height(p + vec2(height_step, 0.0));
	float hz = terrain_height(p + vec2(0.0, height_step));
	NORMAL = normalize(vec3(h - hx, height_step, h - hz));
	VERTEX.y += h;
	v_world_y = VERTEX.y;
	v_world_xz = VERTEX.xz;
}
void fragment() {
	vec2 uv = UV * tex_repeat;
	vec3 albedo = texture(albedo_tex, uv).rgb;
	// 叠加少量程序化色斑，丰富大尺度明暗；轻微绿色增益让地面与草协调
	float patch = fbm3(uv * patch_scale * 3.0);
	float dry = fbm3(uv * patch_scale * 5.0 + 3.1);
	albedo *= (0.90 + 0.18 * patch) * vec3(0.92, 1.12, 0.90);
	albedo = mix(albedo, color_dry, smoothstep(0.72, 0.92, dry) * 0.25);
	// 按海拔着色：低谷更深绿、山脊偏干黄，让地形起伏一眼可辨
	float h01 = clamp((v_world_y + height_amp) / max(height_amp * 2.0, 0.001), 0.0, 1.0);
	albedo *= mix(vec3(0.80, 1.22, 0.72), vec3(1.32, 0.94, 0.64), h01);
	// 云朵阴影：世界坐标锚定的云层缓慢飘移，云下地面变暗
	float cloud = fbm3(v_world_xz * 0.012 + vec2(TIME * 0.04, TIME * 0.028));
	float cloud_shadow = mix(1.0, 0.70, smoothstep(0.52, 0.85, cloud));
	albedo *= cloud_shadow;
	ALBEDO = albedo;
	ROUGHNESS = texture(rough_tex, uv).r;
	// 法线贴图（GL 约定，手动解包）
	vec3 n = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	NORMAL_MAP = n;
}
