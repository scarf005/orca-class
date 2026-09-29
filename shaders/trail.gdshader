shader_type spatial;
// A ribbon that follows a moving flyer: every vertex is placed from the flyer's recent positions
// (`points`: world xyz and the time each was recorded), widened toward the camera and thinner and
// fainter toward its tail. Faded by screen-door, like the other effects. One draw call per ribbon.
render_mode unshaded, cull_disabled;

const int POINTS = 22;

uniform vec4 points[POINTS];
uniform float now = 0.0;
uniform float trail_time = 1.26;
uniform float width = 0.5;
uniform float alpha_scale = 0.6;
uniform vec4 tint : source_color = vec4(1.0);

varying float fade;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	// VERTEX is (side, point index, 0); the node's transform is the identity, so points are in model space.
	int i = int(VERTEX.y + 0.5);
	vec4 here = points[i];
	vec3 dir = points[min(i + 1, POINTS - 1)].xyz - points[max(i - 1, 0)].xyz;
	vec3 side = cross(dir, CAMERA_POSITION_WORLD - here.xyz);
	float len = length(side);
	// A flyer that stood still has no direction: the ribbon collapses to nothing.
	side = len > 0.0001 ? side / len : vec3(0.0);
	float k = float(i) / float(POINTS - 1);
	VERTEX = here.xyz + side * VERTEX.x * width * (1.0 - 0.7 * k);
	fade = clamp(1.0 - (now - here.w) / trail_time, 0.0, 1.0);
}

void fragment() {
	ivec2 px = ivec2(FRAGCOORD.xy);
	float threshold = (BAYER[(px.x & 3) + (px.y & 3) * 4] + 0.5) / 16.0;
	if (fade * alpha_scale < threshold) {
		discard;
	}
	ALBEDO = tint.rgb;
}
