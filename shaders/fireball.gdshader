shader_type spatial;
// A cartoon fireball in hard bands, like an arcade explosion sprite: white-hot where it faces the
// camera, then yellow, orange and red toward the rim. As `progress` runs 0 -> 1 the bands cool into
// dark smoke and the ball erodes away in chunks, from the rim inward.
render_mode unshaded, cull_back, depth_draw_opaque;

instance uniform float progress = 0.0;
instance uniform float seed = 0.0;
uniform vec3 hot : source_color = vec3(1.0, 0.98, 0.86);
uniform vec3 yellow : source_color = vec3(1.0, 0.84, 0.25);
uniform vec3 orange : source_color = vec3(1.0, 0.5, 0.12);
uniform vec3 red : source_color = vec3(0.86, 0.18, 0.16);
uniform vec3 smoke : source_color = vec3(0.23, 0.18, 0.22);

varying vec3 local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3) + seed);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float n = noise(local * 3.0 + seed * 7.0);
	// Rim erodes first; the whole ball is gone by the end.
	if (n * 0.6 + facing * 0.4 < progress * 1.15 - 0.1) {
		discard;
	}
	float heat = facing * 1.1 + (n - 0.5) * 0.35 - progress * 1.3;
	vec3 c = smoke;
	if (heat > 0.75) {
		c = hot;
	} else if (heat > 0.5) {
		c = yellow;
	} else if (heat > 0.25) {
		c = orange;
	} else if (heat > 0.02) {
		c = red;
	}
	ALBEDO = c;
}
