shader_type spatial;
render_mode unshaded, cull_front;

uniform sampler2D sky_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec2 v_uv;

void vertex() {
	// 球面 UV 与 equirect 映射对齐：翻转 V 让 HDRI 顶部对准天顶
	v_uv = vec2(UV.x, 1.0 - UV.y);
}

void fragment() {
	ALBEDO = texture(sky_tex, v_uv).rgb;
}
