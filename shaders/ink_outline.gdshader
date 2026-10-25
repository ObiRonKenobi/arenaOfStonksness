shader_type spatial;
render_mode unshaded, cull_front;

void vertex() {
	VERTEX += NORMAL * 0.022;
}

void fragment() {
	ALBEDO = vec3(0.05, 0.04, 0.03);
}
