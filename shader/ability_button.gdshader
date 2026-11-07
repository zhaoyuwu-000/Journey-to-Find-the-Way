shader_type canvas_item;
// 能力按钮：外描边 + 选中高亮

uniform vec4 highlight_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.0;   // 0 = 不染色
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 32.0) = 8.0;        // 单位：贴图像素

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	// 8 方向采样邻居 alpha：透明像素只要在 outline_width 范围内碰到不透明像素，就画描边
	vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
	float neighbor_a = 0.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * PI / 4.0;
		vec2 dir = vec2(cos(ang), sin(ang));
		neighbor_a = max(neighbor_a, texture(TEXTURE, UV + dir * px).a);
	}

	// 高亮：往 highlight_color 混
	col.rgb = mix(col.rgb, highlight_color.rgb, highlight_strength);

	// 描边
	if (col.a < 0.1 && neighbor_a > 0.05) {
		col = outline_color;
	}

	COLOR = col;
}
