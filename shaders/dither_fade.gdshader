shader_type spatial;
// Screen-door transparency: vertex/instance alpha is compared against a Bayer threshold at the
// low-resolution pixel grid, so fades read as dither instead of blended alpha.
render_mode cull_disabled, depth_draw_opaque;

uniform bool unshaded = false;
uniform float alpha_scale = 1.0;
instance uniform float instance_alpha = 1.0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	ivec2 px = ivec2(FRAGCOORD.xy);
	float threshold = (BAYER[(px.x & 3) + (px.y & 3) * 4] + 0.5) / 16.0;
	if (COLOR.a * alpha_scale * instance_alpha < threshold) {
		discard;
	}
	if (unshaded) {
		EMISSION = COLOR.rgb;
		ALBEDO = vec3(0.0);
	} else {
		ALBEDO = COLOR.rgb;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
