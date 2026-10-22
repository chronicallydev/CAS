// Matching a colour to the nearest palette colour, shared by the 3D colour
// pass (retro_palette.gdshader) and the UI pass (ui_palette.gdshader). The
// palette uniforms are set by RetroPalettes.apply.

const int MAX_COLORS = 32;

// The palette in OKLab (for matching) and in sRGB (for output).
uniform vec3 palette_lab[MAX_COLORS];
uniform vec3 palette_rgb[MAX_COLORS];
uniform int palette_size = 0;


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
