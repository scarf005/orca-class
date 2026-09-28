shader_type spatial;
// Overlay on every enemy: a hot rim along silhouettes, so hostiles read apart from the pastel scenery
// and from friendly or pickup colors at a glance.
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec4 rim_color : source_color = vec4(1.0, 0.208, 0.396, 1.0);
uniform float power = 2.2;
uniform float strength = 0.95;

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	ALBEDO = rim_color.rgb;
	ALPHA = step(0.35, rim) * strength;
}
