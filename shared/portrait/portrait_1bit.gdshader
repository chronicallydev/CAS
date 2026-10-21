// 1-bit character shading for portraits (see character_portrait.gd).
// Lights the model with a fixed key, fill and rim light, then turns the
// lightness straight into black or white pixels with a screen-space
// pattern, so a detailed sculpt keeps its form at low resolution:
//   pattern 0 - 8x8 ordered (Bayer) dither: 64 grey levels
//   pattern 1 - hatching: diagonal lines that thicken and cross-hatch as
//               the surface darkens, like an engraving
// Every part gets its own `tone` (how light its "paint" is) so hair, skin
// and clothes stay apart once colour is gone.
shader_type spatial;
render_mode unshaded, cull_back;

// How light this part is painted, 0 = black, 1 = white.
uniform float tone : hint_range(0.0, 1.0) = 0.8;
// Multiply in the brightness of the vertex paint (sculpts are often
// painted rather than textured).
uniform bool use_vertex_color = false;
// Lights in world space (directions the light travels *from*).
uniform vec3 key_direction = vec3(-0.45, 0.55, 1.0);
uniform float key_strength = 1.0;
uniform vec3 fill_direction = vec3(0.8, 0.1, 0.4);
uniform float fill_strength = 0.4;
uniform float ambient = 0.18;
// Bright edge on the side facing away from the camera.
uniform float rim_strength = 0.9;
uniform float rim_width : hint_range(0.0, 1.0) = 0.35;
// Shine, so dark glossy parts (hair, lenses) still show their form.
uniform float specular_strength = 0.6;
uniform float specular_power = 24.0;
// > 1 pushes mid-tones toward black, < 1 toward white.
uniform float contrast_curve = 1.0;
// Lightness at or below / above which pixels are solid black / white, so
// near-flat areas don't break up into stray dots.
uniform float black_point = 0.1;
uniform float white_point = 0.85;
uniform int pattern = 0;
// Pattern cell size in screen pixels.
uniform float pattern_scale = 1.0;
// Hatching line spacing in pattern cells.
uniform float hatch_spacing = 5.0;

const float BAYER8[64] = float[](
	0.0, 32.0, 8.0, 40.0, 2.0, 34.0, 10.0, 42.0,
	48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
	12.0, 44.0, 4.0, 36.0, 14.0, 46.0, 6.0, 38.0,
	60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
	3.0, 35.0, 11.0, 43.0, 1.0, 33.0, 9.0, 41.0,
	51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
	15.0, 47.0, 7.0, 39.0, 13.0, 45.0, 5.0, 37.0,
	63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0);


float bayer(vec2 pixel) {
	ivec2 p = ivec2(mod(floor(pixel), 8.0));
	return (BAYER8[p.y * 8 + p.x] + 0.5) / 64.0;
}


// 1 where a line of this direction covers the pixel; `width` is the share
// of the spacing the line takes up.
float hatch_line(vec2 pixel, vec2 direction, float width) {
	float position = mod(dot(floor(pixel), direction), hatch_spacing);
	return float(position < width * hatch_spacing);
}


float hatch(vec2 pixel, float light) {
	float dark = 1.0 - light;
	// First layer: one diagonal, thickening as it darkens.
	float ink = hatch_line(pixel, vec2(1.0, 1.0), clamp(dark * 1.3, 0.0, 0.5));
	// Darker: the crossing diagonal.
	ink = max(ink, hatch_line(pixel, vec2(1.0, -1.0), clamp((dark - 0.5) * 1.3, 0.0, 0.5)));
	// Darkest: fill in.
	ink = max(ink, step(0.92, dark));
	return 1.0 - ink;
}


void fragment() {
	vec3 normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 to_camera = normalize((INV_VIEW_MATRIX * vec4(-VERTEX, 0.0)).xyz);

	float key = max(dot(normal, normalize(key_direction)), 0.0);
	float fill = max(dot(normal, normalize(fill_direction)), 0.0);
	float paint = tone;
	if (use_vertex_color) {
		// Vertex colours are linear; judge their brightness by eye.
		paint *= pow(dot(COLOR.rgb, vec3(0.299, 0.587, 0.114)), 1.0 / 2.2);
	}
	float light = paint * (ambient + key * key_strength + fill * fill_strength);

	// Rim: grazing angles, on the side away from the key light.
	float grazing = 1.0 - max(dot(normal, to_camera), 0.0);
	float rim = smoothstep(1.0 - rim_width, 1.0, grazing);
	rim *= 1.0 - key;
	light += rim * rim_strength;

	vec3 half_vector = normalize(normalize(key_direction) + to_camera);
	light += pow(max(dot(normal, half_vector), 0.0), specular_power) * specular_strength;

	light = smoothstep(black_point, white_point, light);
	light = pow(light, contrast_curve);

	vec2 pixel = FRAGCOORD.xy / pattern_scale;
	float on = pattern == 1 ? hatch(pixel, light) : step(bayer(pixel), light);
	ALBEDO = vec3(on);
}
