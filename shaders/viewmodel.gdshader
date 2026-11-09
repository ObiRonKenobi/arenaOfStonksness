shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear;
uniform float squeeze = 0.18;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.xyz *= squeeze;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	ALBEDO = (albedo * texture(albedo_tex, UV)).rgb;
}
