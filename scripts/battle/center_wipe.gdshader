shader_type canvas_item;

// Horizontal centre wipe for the YOUR TURN rule. progress 0.0 hides the rule,
// 1.0 draws all of it; feather softens the leading edge so the reveal does not
// step from pixel to pixel as it travels outwards.
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float feather : hint_range(0.001, 0.25) = 0.02;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 0 at the horizontal centre, 1 at both ends.
	float dist = abs(UV.x - 0.5) * 2.0;
	// At progress 1 the edge sits just past the texture, so the tips stay solid.
	float edge = progress * (1.0 + feather);
	float reveal = 1.0 - smoothstep(edge - feather, edge, dist);
	COLOR = vec4(tex.rgb, tex.a * reveal);
}
