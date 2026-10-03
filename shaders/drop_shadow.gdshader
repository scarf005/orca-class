shader_type spatial;
// Arcade drop shadow: a flat disc under an actor or a shot, drawn as a hard ordered-dither screen
// door so it reads as shadow at any height. Each instance's custom data x is its density (0..1).
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.17, 0.13, 0.25);

varying float density;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	density = INSTANCE_CUSTOM.x;
}

void fragment() {
	// Round disc on the quad, solid in the middle and thinning to the rim.
	float r = length(UV - vec2(0.5)) * 2.0;
	if (r > 1.0) {
		discard;
	}
	ivec2 px = ivec2(FRAGCOORD.xy);
	float threshold = (BAYER[(px.x & 3) + (px.y & 3) * 4] + 0.5) / 16.0;
	if (density * (1.0 - r * r * 0.6) < threshold) {
		discard;
	}
	ALBEDO = tint;
}
