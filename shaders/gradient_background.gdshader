shader_type canvas_item;

// Gradient Background Shader
// Supports multi-color gradients with smooth transitions and optional animation

uniform vec4 color_top : source_color = vec4(0.15, 0.25, 0.45, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.35, 0.15, 0.55, 1.0);
uniform float gradient_angle : hint_range(0.0, 360.0) = 90.0; // Degrees
uniform bool animate = false;
uniform float animation_speed : hint_range(0.0, 2.0) = 0.5;
uniform float animation_intensity : hint_range(0.0, 1.0) = 0.2;

void fragment() {
    // Convert angle to radians
    float angle_rad = radians(gradient_angle);
    
    // Calculate gradient direction vector
    vec2 direction = vec2(cos(angle_rad), sin(angle_rad));
    
    // Calculate gradient position (0.0 to 1.0)
    vec2 uv = UV;
    
    // Optional animation: shift the gradient over time
    if (animate) {
        float time_offset = sin(TIME * animation_speed) * animation_intensity;
        uv.y += time_offset;
    }
    
    // Project UV onto gradient direction
    float gradient_pos = dot(uv - vec2(0.5), direction) + 0.5;
    gradient_pos = clamp(gradient_pos, 0.0, 1.0);
    
    // Smooth interpolation between colors
    vec4 final_color = mix(color_top, color_bottom, gradient_pos);
    
    COLOR = final_color;
}
