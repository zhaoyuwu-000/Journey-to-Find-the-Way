shader_type canvas_item;
// 水流：把水流特效按格重复铺在这段水里，UV 随时间往下滚 → 自上而下流动、上下无缝相接

uniform sampler2D flow_tex : repeat_enable, filter_linear;
uniform float tiles = 1.0;                 // 这段水有几格高
uniform float repeat_scale = 0.5;          // 每几格重复一次贴图（越小纹样越大）
uniform float speed = 0.35;                // 每秒滚多少（1 = 一格/秒）
uniform float offset = 0.0;                // 每条错开一点，别整片同步
uniform float strength : hint_range(0.0, 2.0) = 0.35;
uniform vec4 tint : source_color = vec4(0.86, 0.98, 1.0, 1.0);

void fragment() {
	vec2 uv = vec2(UV.x, UV.y * tiles * repeat_scale + offset - TIME * speed);
	vec2 tiled = fract(uv);                 // 上下循环，接下一格继续
	vec4 c = texture(flow_tex, tiled);
	// 只在整段水的两端稍微淡一点，中间保持连续
	float edge = smoothstep(0.0, 0.06, UV.y) * smoothstep(0.0, 0.06, 1.0 - UV.y);
	COLOR = vec4(tint.rgb, c.a * strength * tint.a * edge);
}
