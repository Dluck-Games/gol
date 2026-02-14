shader_type canvas_item;

uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Flash effect - blend with flash color
	vec3 flashed = mix(tex_color.rgb, flash_color.rgb, flash_intensity);
	
	// Add brightness boost when hit
	flashed += flash_intensity * 0.3;
	
	// Dissolve effect for extra impact
	float dissolve = step(dissolve_amount, tex_color.a);
	
	COLOR = vec4(flashed, tex_color.a * dissolve);
}
