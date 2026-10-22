// 1-bit pass on the low-res UI image (see pixel_art.gd): every pixel comes
// out black or white by its lightness, and see-through parts (dimmed
// backdrops, fades) become a 4x4 ordered dither of solid pixels instead of
// a blend, like the 3D image's dither.
shader_type canvas_item;

// Where a colour flips from black to white.
uniform float threshold = 0.5;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);


void fragment() {
	vec4 color = texture(TEXTURE, UV);
	ivec2 cell = ivec2(floor(UV / TEXTURE_PIXEL_SIZE)) % 4;
	float bayer = (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0;
	float lightness = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(step(threshold, lightness)), step(bayer, color.a));
}
