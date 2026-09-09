shader_type sky;
uniform vec3 sky_top : source_color = vec3(0.20, 0.48, 0.90);
uniform vec3 sky_horizon : source_color = vec3(0.72, 0.84, 1.00);
uniform vec3 ground_horizon : source_color = vec3(0.55, 0.62, 0.50);
uniform vec3 ground_bottom : source_color = vec3(0.18, 0.26, 0.18);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_scale : hint_range(0.05, 3.0) = 0.5;
uniform vec2 cloud_wind = vec2(0.012, 0.006);
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
void sky() {
	vec3 dir = normalize(EYEDIR);
	float y = dir.y;
	// 蓝天渐变：地平线淡蓝 -> 头顶深蓝
	vec3 col = mix(sky_horizon, sky_top, pow(clamp(y, 0.0, 1.0), 0.65));
	// 地平线以下：草地反射的暗绿色
	col = mix(col, mix(ground_horizon, ground_bottom, pow(clamp(-y, 0.0, 1.0), 0.8)), step(0.0, -y));
	// 云层（上半球）：fbm 噪声，随时间缓慢飘动
	if (y > 0.03) {
		vec2 uv = (dir.xz / (y + 0.12)) * cloud_scale + cloud_wind * TIME;
		float n = fbm(uv * 1.6);
		float cloud = smoothstep(1.0 - cloud_cover, 1.15 - cloud_cover, n);
		cloud *= smoothstep(0.02, 0.15, y); // 贴近地平线变薄
		col = mix(col, cloud_color, clamp(cloud, 0.0, 1.0) * 0.92);
	}
	COLOR = col;
}
