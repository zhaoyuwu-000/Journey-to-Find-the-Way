shader_type canvas_item;
// 顶部对话框底：椭圆形软边，四周渐淡消融

uniform vec4 tint : source_color = vec4(0.04, 0.09, 0.08, 0.62);
uniform float softness : hint_range(0.05, 1.0) = 0.62;

void fragment() {
	vec2 c = (UV - vec2(0.5)) * 2.0;      // -1..1
	float d = length(c);                  // 到中心归一化距离（正好铺满矩形＝椭圆）
	float a = tint.a * (1.0 - smoothstep(1.0 - softness, 1.0, d));
	COLOR = vec4(tint.rgb, a);
}
