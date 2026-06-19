shader_type canvas_item;

// Enhanced Circle Shader with Glow and Border Support

uniform bool enable_glow = false;
uniform vec4 glow_color : source_color = vec4(0.4, 0.6, 1.0, 0.5);
uniform float glow_width : hint_range(0.0, 0.2) = 0.05;
uniform bool enable_border = false;
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float border_width : hint_range(0.0, 0.1) = 0.02;
uniform float smoothness : hint_range(0.001, 0.05) = 0.005;

void fragment() {
    vec2 center = vec2(0.5);
    float dist = distance(UV, center);
    
    // Main circle with improved anti-aliasing
    float circle_alpha = smoothstep(0.5, 0.5 - smoothness, dist);
    
    // Border effect
    float border_alpha = 0.0;
    if (enable_border) {
        float inner_edge = 0.5 - border_width;
        border_alpha = smoothstep(inner_edge - smoothness, inner_edge, dist) * 
                       smoothstep(0.5, 0.5 - smoothness, dist);
    }
    
    // Glow effect (outer ring)
    float glow_alpha = 0.0;
    if (enable_glow) {
        float glow_start = 0.5;
        float glow_end = 0.5 + glow_width;
        glow_alpha = smoothstep(glow_end, glow_start, dist) * 
                     (1.0 - smoothstep(0.5, 0.5 - smoothness, dist));
    }
    
    // Combine effects
    vec3 final_color = COLOR.rgb;
    float final_alpha = COLOR.a * circle_alpha;
    
    if (enable_border && border_alpha > 0.0) {
        final_color = mix(final_color, border_color.rgb, border_alpha);
        final_alpha = max(final_alpha, border_alpha * border_color.a);
    }
    
    if (enable_glow && glow_alpha > 0.0) {
        final_color = mix(final_color, glow_color.rgb, glow_alpha * glow_color.a);
        final_alpha = max(final_alpha, glow_alpha * glow_color.a);
    }
    
    COLOR = vec4(final_color, final_alpha);
}
