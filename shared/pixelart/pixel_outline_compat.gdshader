// The outline pass (pixel_outline.gdshader) for the Compatibility renderer,
// which the web build uses: it has no normal-roughness buffer, so this
// keeps the dark silhouette lines where depth jumps and drops the light
// crease lines and the roughness-0 opt-out. Same uniforms, so pixel_art.gd
// can set either.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

uniform float depth_threshold = 0.9;
uniform float normal_threshold = 0.2;
uniform float line_highlight = 0.22;
uniform float line_shadow = 1.0;
uniform float color_levels = 28.0;
uniform float saturation = 1.05;


float linear_depth(vec2 uv, mat4 inv_projection) {
	// Compatibility keeps depth in 0..1; NDC z runs -1..1.
	float depth = texture(DEPTH_TEXTURE, uv).x * 2.0 - 1.0;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = inv_projection * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 texel = 1.0 / VIEWPORT_SIZE.xy;
	vec2 offsets[4] = vec2[](vec2(0.0, -1.0), vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(-1.0, 0.0));

	float depth = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float farther = 0.0;
	for (int i = 0; i < 4; i++) {
		float d = linear_depth(SCREEN_UV + offsets[i] * texel, INV_PROJECTION_MATRIX);
		farther += clamp(d - depth, 0.0, depth_threshold * 2.0);
	}
	float silhouette = smoothstep(depth_threshold, depth_threshold * 1.2, farther);

	vec3 color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	color -= color * silhouette * line_shadow;

	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(grey), color, saturation);

	if (color_levels > 0.0) {
		color = floor(color * color_levels + 0.5) / color_levels;
	}

	ALBEDO = max(color, vec3(0.0));
}
