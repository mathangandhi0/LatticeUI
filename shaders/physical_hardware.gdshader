shader_type canvas_item;

uniform sampler2D normal_map : hint_normal;
uniform sampler2D emission_texture : source_color;
uniform float emission_strength : hint_range(0.0, 5.0) = 1.5;

void fragment() {
	vec4 albedo = texture(TEXTURE, UV);
	
	// Convert normal texture from [0, 1] to [-1, 1] range
	vec3 normal = texture(normal_map, UV).rgb * 2.0 - 1.0;
	
	// Sample the emission texture
	vec4 emission = texture(emission_texture, UV);
	
	// Apply emission glow directly to the RGB channels
	COLOR.rgb = albedo.rgb + (emission.rgb * emission_strength);
	COLOR.a = albedo.a;
	
	// Write to the NORMAL buffer so PointLight2D can calculate shadows and specular reflections
	NORMAL = normal;
}
