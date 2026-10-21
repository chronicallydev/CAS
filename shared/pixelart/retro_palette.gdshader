// Retro colour pass on the upscaled pixel-art image (see pixel_art.gd).
// Each low-res pixel is snapped to a limited set of colours, with 4x4
// ordered (Bayer) dithering where the true colour falls between two:
//   mode 0 - off
//   mode 1 - nearest colour from a fixed palette, matched in OKLab so the
//            pick looks right to the eye rather than in raw RGB
//   mode 2 - per-channel levels, like a console's 9-bit colour (8 levels
//            per channel = the Mega Drive's 512 colours)
// The dither pattern is offset by the camera's whole-pixel position, so it
// stays stuck to the ground as the view scrolls instead of crawling.
shader_type canvas_item;

const int MAX_COLORS = 32;

uniform int mode = 0;
// The palette in OKLab (for matching) and in sRGB (for output).
uniform vec3 palette_lab[MAX_COLORS];
uniform vec3 palette_rgb[MAX_COLORS];
uniform int palette_size = 0;
// Monochrome palettes (Game Boy, black & white): pick by lightness alone,
// dithering between the two shades either side. Their colours must be
// listed dark to light. The curve darkens (> 1) or lightens (< 1) the
// image first, as the bright desert would otherwise come out nearly white.
uniform bool lightness_only = false;
uniform float lightness_curve = 1.0;
// Steps per channel in levels mode.
uniform float levels = 8.0;
// 0 = hard banding, 1 = a full step of dither noise.
uniform float dither = 0.5;
// The camera's position in low-res pixels (set by pixel_art.gd).
uniform ivec2 dither_offset = ivec2(0);
// Inverts the whole image (the 1-bit damage flash; see PixelArt.invert_flash).
uniform bool invert = false;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);


vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}


// sRGB to OKLab (Björn Ottosson).
vec3 to_oklab(vec3 srgb) {
	vec3 c = to_linear(clamp(srgb, 0.0, 1.0));
	vec3 lms = vec3(
		0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
		0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
		0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
	lms = pow(lms, vec3(1.0 / 3.0));
	return vec3(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}


vec3 nearest(vec3 srgb) {
	vec3 lab = to_oklab(srgb);
	float best = 1e9;
	vec3 pick = srgb;
	for (int i = 0; i < MAX_COLORS; i++) {
		if (i >= palette_size) {
			break;
		}
		vec3 d = lab - palette_lab[i];
		float dist = dot(d, d);
		if (dist < best) {
			best = dist;
			pick = palette_rgb[i];
		}
	}
	return pick;
}


vec3 shade(vec3 srgb, float threshold) {
	float l = pow(clamp(to_oklab(srgb).x, 0.0, 1.0), lightness_curve);
	// The first shade at least this light, and the one below it.
	int upper = palette_size - 1;
	for (int i = 1; i < MAX_COLORS; i++) {
		if (i >= palette_size) {
			break;
		}
		if (l <= palette_lab[i].x) {
			upper = i;
			break;
		}
	}
	int lower = max(upper - 1, 0);
	float span = max(palette_lab[upper].x - palette_lab[lower].x, 1e-4);
	float t = clamp((l - palette_lab[lower].x) / span, 0.0, 1.0);
	return t > 0.5 + threshold * dither ? palette_rgb[upper] : palette_rgb[lower];
}


void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (mode == 0) {
		COLOR = source;
	} else {
		// Which low-res pixel this is, in world-stable terms.
		ivec2 pixel = ivec2(floor(UV / TEXTURE_PIXEL_SIZE)) + dither_offset;
		ivec2 cell = ((pixel % 4) + 4) % 4;
		float threshold = (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0 - 0.5;

		vec3 color;
		if (mode == 1 && lightness_only) {
			color = shade(source.rgb, threshold);
		} else if (mode == 1) {
			color = nearest(source.rgb + threshold * dither * 0.25);
		} else {
			float steps = max(levels - 1.0, 1.0);
			color = clamp(floor(source.rgb * steps + 0.5 + threshold * dither) / steps, 0.0, 1.0);
		}
		COLOR = vec4(color, source.a);
	}
	if (invert) {
		COLOR.rgb = vec3(1.0) - COLOR.rgb;
	}
}
