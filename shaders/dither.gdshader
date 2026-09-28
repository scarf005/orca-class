shader_type canvas_item;
// Ordered-dither palette quantization of the low-resolution 3D view.
// The Bayer matrix is indexed by source pixel, so the pattern stays fixed to the screen grid.

uniform vec3 palette_lab[32];
uniform vec3 palette_rgb[32];
uniform int palette_size = 1;
uniform float spread = 0.08;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 flash = vec4(0.0); // Full-screen tint for hits and big blasts; alpha is the mix.
uniform sampler2D actor_mask : filter_nearest; // Alpha > 0 where actors and flames are drawn.
// Actors (the tank, enemies, pickups, shots, flames) are shown in their true colors, never quantized
// to the pastel palette, so they stand out from the scenery. Enemies and pickups also get a glowing
// outline; their half-resolution masks only give the silhouette.
uniform sampler2D hostile_mask : filter_nearest;
uniform sampler2D loot_mask : filter_nearest;
uniform vec4 outline_colors[2];

float coverage(sampler2D mask, vec2 uv, vec2 texel, float radius) {
	float hit = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.78539816;
		hit = max(hit, texture(mask, uv + vec2(cos(a), sin(a)) * texel * radius).a);
	}
	return step(0.5, hit);
}

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 to_oklab(vec3 c) {
	vec3 lms = mat3(vec3(0.4122214708, 0.2119034982, 0.0883024619), vec3(0.5363325363, 0.6806995451, 0.2817188376), vec3(0.0514459929, 0.1073969566, 0.6299787005)) * c;
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	return mat3(vec3(0.2104542553, 1.9779984951, 0.0259040371), vec3(0.7936177850, -2.4285922050, 0.7827717662), vec3(-0.0040720468, 0.4505937099, -0.8086757660)) * lms;
}

void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	ivec2 px = ivec2(floor(UV * size));
	vec3 color = texture(TEXTURE, UV).rgb;
	color = mix(color, flash.rgb, flash.a);
	float threshold = (BAYER[(px.x & 3) + (px.y & 3) * 4] + 0.5) / 16.0 - 0.5;
	vec3 result = color;
	if (texture(actor_mask, UV).a < 0.5) {
		vec3 lab = to_oklab(to_linear(clamp(color + threshold * spread * strength, 0.0, 1.0)));
		// Chroma errors cost more than lightness errors, so dithering mixes shades of one hue
		// instead of speckling unrelated hues together.
		vec3 weight = vec3(1.0, 1.7, 1.7);
		float best = 1e9;
		for (int i = 0; i < palette_size; i++) {
			vec3 d = (lab - palette_lab[i]) * weight;
			float dist = dot(d, d);
			if (dist < best) {
				best = dist;
				result = palette_rgb[i];
			}
		}
		// Around each outlined actor, a solid rim and a dithered glow beyond it.
		vec2 texel = 1.0 / vec2(textureSize(hostile_mask, 0));
		float glow_dither = BAYER[(px.x & 3) + (px.y & 3) * 4] / 16.0;
		for (int k = 0; k < 2; k++) {
			float rim = k == 0 ? coverage(hostile_mask, UV, texel, 1.0) : coverage(loot_mask, UV, texel, 1.0);
			float halo = k == 0 ? coverage(hostile_mask, UV, texel, 2.5) : coverage(loot_mask, UV, texel, 2.5);
			if (rim > 0.5) {
				result = outline_colors[k].rgb;
			} else if (halo > 0.5 && glow_dither < 0.5) {
				result = mix(result, outline_colors[k].rgb, 0.6);
			}
		}
	}
	COLOR = vec4(result, 1.0);
}
