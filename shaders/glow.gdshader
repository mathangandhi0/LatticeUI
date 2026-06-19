shader_type canvas_item;

// Glow Shader for Icons and UI Elements
// Provides configurable glow effect with smooth falloff

uniform vec4 glow_color : source_color = vec4(0.4, 0.6, 1.0, 0.5);
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float glow_size : hint_range(0.0, 0.3) = 0.1;
uniform bool animate_glow = false;
uniform float time_scale : hint_range(0.0, 5.0) = 1.0;

void fragment() {
    // Get the texture color
    vec4 tex_color = texture(TEXTURE, UV);
    
    // Calculate distance from center for radial glow
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    
    // Animated glow intensity (optional)
    float anim_intensity = glow_intensity;
    if (animate_glow) {
        anim_intensity *= 0.7 + 0.3 * sin(TIME * time_scale);
    }
    
    // Create glow effect
    // Inner glow: stronger near the edges of the texture
    float edge_dist = 1.0 - tex_color.a;
    float inner_glow = smoothstep(0.0, glow_size, edge_dist) * anim_intensity;
    
    // Outer glow: extends beyond the texture
    float outer_glow = smoothstep(glow_size * 2.0, 0.0, dist - 0.5) * anim_intensity * 0.5;
    
    // Combine glows
    float total_glow = max(inner_glow, outer_glow);
    
    // Mix original color with glow
    vec3 final_color = mix(tex_color.rgb, glow_color.rgb, total_glow * glow_color.a);
    float final_alpha = max(tex_color.a, total_glow * glow_color.a);
    
    COLOR = vec4(final_color, final_alpha);
}
