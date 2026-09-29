shader_type spatial;
// Debris shards: each instance draws one layer of the sprite array (its custom data picks which),
// in the sprite's own colors times the instance color. Fades by the same Bayer screen door as the
// other effects.
render_mode cull_disabled, depth_draw_opaque, unshaded;

uniform sampler2DArray sprites : filter_nearest;
uniform bool particles = false;

varying float layer;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	layer = INSTANCE_CUSTOM.x;
	if (particles) {
		float c = cos(INSTANCE_CUSTOM.z);
		float s = sin(INSTANCE_CUSTOM.z);
		VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
		VERTEX = mat3(INV_VIEW_MATRIX) * VERTEX * INSTANCE_CUSTOM.y;
	}
}

void fragment() {
	vec4 texel = texture(sprites, vec3(UV, layer));
	ivec2 px = ivec2(FRAGCOORD.xy);
	float threshold = (BAYER[(px.x & 3) + (px.y & 3) * 4] + 0.5) / 16.0;
	if (texel.a * COLOR.a < threshold) {
		discard;
	}
	ALBEDO = texel.rgb * COLOR.rgb;
}
