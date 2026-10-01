shader_type spatial;
// Screen-door transparency: vertex/instance alpha is compared against a Bayer threshold at the
// low-resolution pixel grid, so fades read as dither instead of blended alpha.
render_mode cull_disabled, depth_draw_opaque;

uniform bool unshaded = false;
uniform bool hard_cut = false; // Flames: vanish at a clean edge instead of a screen-door pattern.
uniform bool particles = false; // MultiMesh size and Euler rotation; ordinary effect meshes stay unchanged.
uniform float alpha_scale = 1.0;
instance uniform float instance_alpha = 1.0;
instance uniform vec4 instance_tint = vec4(0.0); // rgb replaces the vertex color by its alpha (afterimages).

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	if (particles) {
		float age = INSTANCE_CUSTOM.x;
		float t = age / MODEL_MATRIX[2][0];
		float size = mix(MODEL_MATRIX[0][0], MODEL_MATRIX[1][0], t);
		vec3 angles = vec3(MODEL_MATRIX[1][1], MODEL_MATRIX[2][1], MODEL_MATRIX[0][2]) * age;
		COLOR.a = 1.0 - smoothstep(MODEL_MATRIX[0][1], 1.0, t);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX);
		vec3 c = cos(angles);
		vec3 s = sin(angles);
		// Basis.from_euler uses YXZ order: apply Z, then X, then Y.
		mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c.x, s.x), vec3(0.0, -s.x, c.x));
		mat3 ry = mat3(vec3(c.y, 0.0, -s.y), vec3(0.0, 1.0, 0.0), vec3(s.y, 0.0, c.y));
		mat3 rz = mat3(vec3(c.z, s.z, 0.0), vec3(-s.z, c.z, 0.0), vec3(0.0, 0.0, 1.0));
		mat3 rotation = ry * rx * rz;
		VERTEX = rotation * VERTEX * size;
		NORMAL = rotation * NORMAL;
	}
}

void fragment() {
	ivec2 px = ivec2(FRAGCOORD.xy);
	float threshold = (BAYER[(px.x & 3) + (px.y & 3) * 4] + 0.5) / 16.0;
	if (COLOR.a * alpha_scale * instance_alpha < (hard_cut ? 0.5 : threshold)) {
		discard;
	}
	vec3 color = mix(COLOR.rgb, instance_tint.rgb, instance_tint.a);
	if (unshaded) {
		EMISSION = color;
		ALBEDO = vec3(0.0);
	} else {
		ALBEDO = color;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
