// River between the boards: flat cartoon water with drifting highlight streaks (world-space).
shader_type spatial;
render_mode unshaded;

uniform vec4 deep : source_color = vec4(0.22, 0.66, 0.78, 1.0);
uniform vec4 shallow : source_color = vec4(0.42, 0.82, 0.88, 1.0);
uniform vec4 streak : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform float bank_z = 0.75;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge = smoothstep(bank_z * 0.55, bank_z, abs(wpos.z));
	vec3 col = mix(deep.rgb, shallow.rgb, edge);
	float w = sin(wpos.x * 2.2 + TIME * 1.2 + sin(wpos.z * 5.0 + TIME * 0.7) * 1.4);
	float s = smoothstep(0.93, 0.99, w) * (1.0 - edge * 0.7);
	ALBEDO = mix(col, streak.rgb, s * 0.7);
}
