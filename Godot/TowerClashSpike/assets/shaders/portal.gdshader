// Enemy spawn portal: animated purple swirl on a flat disc (PlaneMesh UVs 0..1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 dark : source_color = vec4(0.12, 0.02, 0.22, 1.0);
uniform vec4 mid : source_color = vec4(0.45, 0.12, 0.75, 1.0);
uniform vec4 bright : source_color = vec4(0.85, 0.55, 1.0, 1.0);
uniform float speed = 3.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float s = sin(a * 3.0 + r * 9.0 - TIME * speed);
	vec3 col = mix(mid.rgb, bright.rgb, smoothstep(0.2, 0.9, s) * (1.0 - r * 0.5));
	col = mix(dark.rgb, col, smoothstep(0.08, 0.45, r));
	float rim = smoothstep(0.82, 0.97, r);
	col = mix(col, bright.rgb, rim * 0.8);
	ALBEDO = col + bright.rgb * pulse * (1.0 - r);
	ALPHA = 1.0 - smoothstep(0.96, 1.0, r);
}
