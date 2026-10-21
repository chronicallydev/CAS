shader_type spatial;

// Campaign map ground: vertex-coloured terrain tinted by the region that
// owns it, with glowing borders. Owned land is green, enemy land red;
// regions you can attack get a pulsing border. Unreachable land is dimmed.

// Region index + 1 per texel (0 = nobody).
uniform sampler2D region_ids : filter_nearest, repeat_disable;
// Distance to the region's edge, 0-1 over border_range texels.
uniform sampler2D region_border : filter_linear, repeat_disable;
// xy = world min corner (x, z), zw = size.
uniform vec4 region_rect;
uniform float border_range = 16.0;

// Per region: 1 = owned, 2 = can attack, 3 = out of reach.
uniform int region_state[8];
uniform int hovered = -1;
uniform int selected = -1;

uniform vec3 owned_color : source_color = vec3(0.3, 0.95, 0.4);
uniform vec3 enemy_color : source_color = vec3(1.0, 0.22, 0.16);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ground = COLOR.rgb;
	vec3 albedo = ground;
	vec3 emission = vec3(0.0);

	vec2 uv = (world_position.xz - region_rect.xy) / region_rect.zw;
	if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
		int id = int(round(texture(region_ids, uv).r * 255.0)) - 1;
		if (id >= 0) {
			int state = region_state[id];
			vec3 tint = state == 1 ? owned_color : enemy_color;
			float d = texture(region_border, uv).r * border_range;

			float fill = state == 3 ? 0.06 : 0.1;
			if (state == 3) {
				ground *= 0.78;
			}
			if (id == hovered) {
				fill += 0.08;
			}
			if (id == selected) {
				fill += 0.12;
			}

			// Soft glow just inside the border, then the border line itself.
			float glow = (1.0 - smoothstep(0.0, 6.0, d)) * 0.22;
			albedo = mix(ground, tint, fill + glow);

			float pulse = state == 2 ? 0.5 + 0.5 * sin(TIME * 4.0) : 0.0;
			float width = 0.8 + pulse * 0.8 + (id == selected ? 0.5 : 0.0);
			float line = 1.0 - smoothstep(width, width + 1.4, d);
			albedo = mix(albedo, tint, line);
			emission = tint * line * (0.35 + pulse * 1.2 + (id == selected ? 0.5 : 0.0));
		}
	}

	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
