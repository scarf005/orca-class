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
uniform float actor_dither = 0.15; // Fraction of the dither spread kept on actors.
// Per-class masks: enemies, the tank, pickups. Each gets a glowing outline in its class color and is
// shown in its true colors, not quantized to the pastel palette, so it stands out from the scenery.
uniform sampler2D hostile_mask : filter_nearest;
uniform sampler2D friendly_mask : filter_nearest;
uniform sampler2D loot_mask : filter_nearest;
uniform vec4 class_colors[3];

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
	float actor = step(0.5, texture(actor_mask, UV).a);
	float amount = spread * strength * mix(1.0, actor_dither, actor);
	vec3 lab = to_oklab(to_linear(clamp(color + threshold * amount, 0.0, 1.0)));
	// Chroma errors cost more than lightness errors, so dithering mixes shades of one hue
	// instead of speckling unrelated hues together.
	vec3 weight = vec3(1.0, 1.7, 1.7);
	float best = 1e9;
	vec3 result = color;
	for (int i = 0; i < palette_size; i++) {
		vec3 d = (lab - palette_lab[i]) * weight;
		float dist = dot(d, d);
		if (dist < best) {
			best = dist;
			result = palette_rgb[i];
		}
	}
	// Class actors keep their real color; around each, a solid rim and a dithered glow beyond it.
	vec2 texel = 1.0 / size;
	float glow_dither = BAYER[(px.x & 3) + (px.y & 3) * 4] / 16.0;
	for (int k = 0; k < 3; k++) {
		float inside = k == 0 ? texture(hostile_mask, UV).a : (k == 1 ? texture(friendly_mask, UV).a : texture(loot_mask, UV).a);
		if (inside > 0.5) {
			result = color;
			continue;
		}
		if (class_colors[k].a < 0.5) {
			continue;
		}
		float rim = k == 0 ? coverage(hostile_mask, UV, texel, 2.0) : (k == 1 ? coverage(friendly_mask, UV, texel, 2.0) : coverage(loot_mask, UV, texel, 2.0));
		float halo = k == 0 ? coverage(hostile_mask, UV, texel, 5.0) : (k == 1 ? coverage(friendly_mask, UV, texel, 5.0) : coverage(loot_mask, UV, texel, 5.0));
		if (rim > 0.5) {
			result = class_colors[k].rgb;
		} else if (halo > 0.5 && glow_dither < 0.5) {
			result = mix(result, class_colors[k].rgb, 0.6);
		}
	}
	COLOR = vec4(result, 1.0);
}
