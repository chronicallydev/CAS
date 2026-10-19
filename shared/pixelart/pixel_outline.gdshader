// Full-screen pixel-art outline pass, drawn by the low-res pixel camera
// (see pixel_art.gd). Dark lines where depth jumps (object silhouettes),
// light lines on creases where the surface normal changes, plus a light
// colour posterize.
//
// Adapted from the edge-detection shader in "3D Pixel Art - Tutorial" by
// Eduardo Schildt (MIT), which builds on Kody King's three.js pixel demo.
// Materials with roughness 0 get no outline.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;
uniform sampler2D NORMAL_TEXTURE : hint_normal_roughness_texture, filter_nearest;

// Depth gap (world units) between neighbouring pixels that counts as a silhouette.
uniform float depth_threshold = 0.9;
uniform float normal_threshold = 0.2;
// Brightening of crease lines and darkening of silhouette lines.
uniform float line_highlight = 0.22;
uniform float line_shadow = 0.5;
// Colour steps per channel (0 = off) and a saturation boost.
uniform float color_levels = 28.0;
uniform float saturation = 1.05;


float linear_depth(vec2 uv, mat4 inv_projection, float mask) {
	// Raw depth to linear depth, from the Godot advanced post-processing docs.
	float depth = texture(DEPTH_TEXTURE, uv).x * mask;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = inv_projection * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

vec3 view_normal(vec2 uv) {
	return texture(NORMAL_TEXTURE, uv).rgb * 2.0 - 1.0;
}

float normal_edge(vec3 normal, vec3 neighbour) {
	// Only draw on one side of the crease so lines stay one pixel wide.
	float difference = dot(normal - neighbour, vec3(1.0));
	float side = clamp(smoothstep(-0.01, 0.01, difference), 0.0, 1.0);
	return (1.0 - dot(normal, neighbour)) * side;
}

void vertex() {
	// Cover the whole screen regardless of where the quad is.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 texel = 1.0 / VIEWPORT_SIZE.xy;
	vec2 offsets[4] = vec2[](vec2(0.0, -1.0), vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(-1.0, 0.0));

	// Roughness 0 (alpha of the normal buffer) opts out of outlines; so do
	// pixels with no geometry.
	float mask = ceil(texture(NORMAL_TEXTURE, SCREEN_UV).a);

	float depth = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX, mask);
	float farther = 0.0;
	float nearer = 0.0;
	for (int i = 0; i < 4; i++) {
		float d = linear_depth(SCREEN_UV + offsets[i] * texel, INV_PROJECTION_MATRIX, mask);
		farther += clamp(d - depth, 0.0, depth_threshold * 2.0);
		nearer += depth - d;
	}
	// Silhouette: a neighbour is far behind this pixel.
	float silhouette = smoothstep(depth_threshold, depth_threshold * 1.2, farther);
	// This pixel is itself behind an edge: no crease line here.
	float behind = step(depth_threshold * 0.6, nearer);

	vec3 normal = view_normal(SCREEN_UV);
	float crease = 0.0;
	for (int i = 0; i < 4; i++) {
		crease += normal_edge(normal, view_normal(SCREEN_UV + offsets[i] * texel));
	}
	crease = step(normal_threshold, crease) * mask;
	crease = clamp(crease - behind - silhouette, 0.0, 1.0);

	vec3 color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	color += color * crease * line_highlight + crease * line_highlight * 0.08;
	color -= color * silhouette * line_shadow * mask;

	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(grey), color, saturation);

	if (color_levels > 0.0) {
		color = floor(color * color_levels + 0.5) / color_levels;
	}

	ALBEDO = max(color, vec3(0.0));
}
