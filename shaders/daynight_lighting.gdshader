shader_type canvas_item;

// 环境光颜色 (昼夜变化)
uniform vec4 ambient_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 光源数据 (最多支持 16 个光源)
uniform vec2 light_positions[16];
uniform vec4 light_colors[16];
uniform float light_radii[16];
uniform float light_intensities[16];
uniform int light_count = 0;

// 屏幕尺寸 (用于坐标转换)
uniform vec2 screen_size = vec2(1920.0, 1080.0);

// 屏幕纹理
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	// 获取屏幕原始颜色
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	
	// 从环境光开始
	vec3 final_color = screen_color.rgb * ambient_color.rgb;
	
	// 当前像素的屏幕坐标 (使用 SCREEN_UV * screen_size)
	vec2 frag_pos = SCREEN_UV * screen_size;
	
	// 计算每个光源的贡献
	for (int i = 0; i < light_count && i < 16; i++) {
		vec2 light_pos = light_positions[i];
		vec4 light_color = light_colors[i];
		float radius = light_radii[i];
		float intensity = light_intensities[i];
		
		// 计算当前像素到光源的距离
		float dist = distance(frag_pos, light_pos);
		
		// 平滑衰减 (二次衰减 + 平滑边缘)
		float attenuation = 1.0 - smoothstep(0.0, radius, dist);
		attenuation = attenuation * attenuation; // 二次衰减更自然
		
		// 光源贡献：在环境光基础上添加光照
		// 光照区域内逐渐恢复到原始颜色，并叠加光源颜色
		vec3 lit_color = screen_color.rgb * light_color.rgb * intensity;
		final_color = mix(final_color, lit_color, attenuation);
	}
	
	COLOR = vec4(final_color, screen_color.a);
}
