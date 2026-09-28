shader_type spatial;
// Living fungus: a slow peristaltic swell that travels up the mass. The offset is a continuous
// function of position, so flat-shaded faces that share corners stay sealed.

uniform bool glow = false;
uniform float amplitude = 0.07;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(TIME * 2.3 - world.y * 1.6 + world.x * 0.35 + world.z * 0.35);
	float twitch = sin(TIME * 7.1 + world.x * 3.0 + world.z * 2.0) * 0.15;
	VERTEX += vec3(VERTEX.x, VERTEX.y * 0.25, VERTEX.z) * amplitude * (wave + twitch);
}

void fragment() {
	if (glow) {
		ALBEDO = vec3(0.0);
		EMISSION = COLOR.rgb * (0.85 + 0.15 * sin(TIME * 4.0));
	} else {
		ALBEDO = COLOR.rgb;
		ROUGHNESS = 0.55;
		SPECULAR = 0.45;
	}
}
