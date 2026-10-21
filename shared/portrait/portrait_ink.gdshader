// Ink lines for portraits (see character_portrait.gd), a full-screen quad
// in the portrait's own viewport. Draws black where depth jumps (one part
// in front of another: hair over the face, the glasses' frame) and on
// sharp creases, after the 1-bit shading has already been drawn.
// Same edge tests as pixel_outline.gdshader, but with ink only.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;
uniform sampler2D NORMAL_TEXTURE : hint_normal_roughness_texture, filter_nearest;

// Depth gap (world units) between neighbouring pixels that counts as an edge.
uniform float depth_threshold = 0.04;
// Normal change that counts as a crease (0 = off).
uniform float crease_threshold = 0.6;
// 0 = no lines, 1 = full ink.
uniform float silhouette_ink = 1.0;
uniform float crease_ink = 1.0;
// Colour of the empty background.
uniform float background = 1.0;


float linear_depth(vec2 uv, mat4 inv_projection) {
	float depth = texture(DEPTH_TEXTURE, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = inv_projection * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}


vec3 view_normal(vec2 uv) {
	return texture(NORMAL_TEXTURE, uv).rgb * 2.0 - 1.0;
}


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


void fragment() {
	vec2 texel = 1.0 / VIEWPORT_SIZE.xy;
	vec2 offsets[4] = vec2[](vec2(0.0, -1.0), vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(-1.0, 0.0));

	// No geometry here: plain background.
	// (Reverse-Z: the far plane is 0.)
	float mask = step(1e-7, texture(DEPTH_TEXTURE, SCREEN_UV).x);

	float depth = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float farther = 0.0;
	for (int i = 0; i < 4; i++) {
		float d = linear_depth(SCREEN_UV + offsets[i] * texel, INV_PROJECTION_MATRIX);
		farther = max(farther, d - depth);
	}
	// Lines go on the nearer side of a depth jump, so they hug the front part.
	float silhouette = step(depth_threshold, farther) * mask;

	float crease = 0.0;
	if (crease_threshold > 0.0) {
		vec3 normal = view_normal(SCREEN_UV);
		for (int i = 0; i < 4; i++) {
			vec3 neighbour = view_normal(SCREEN_UV + offsets[i] * texel);
			// One side of the crease only, to keep lines one pixel wide.
			float side = step(0.0, dot(normal - neighbour, vec3(1.0)));
			crease = max(crease, (1.0 - dot(normal, neighbour)) * side);
		}
		crease = step(crease_threshold, crease) * mask;
	}

	float color = texture(SCREEN_TEXTURE, SCREEN_UV).r;
	color = mix(background, color, mask);
	color *= 1.0 - max(silhouette * silhouette_ink, crease * crease_ink);
	ALBEDO = vec3(color);
}
