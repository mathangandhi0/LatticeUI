shader_type canvas_item;

// Premium 3-Color Slanted Gradient
// Transitions smoothly through three color points (Start -> Mid -> End)

uniform vec4 color_start : source_color = vec4(0.0, 0.4, 1.0, 1.0); // Blue
uniform vec4 color_mid : source_color = vec4(0.5, 0.0, 1.0, 1.0);   // Violet
uniform vec4 color_end : source_color = vec4(1.0, 0.2, 0.6, 1.0);   // Pink
uniform float angle : hint_range(0.0, 360.0) = 135.0;              // Slanted angle
uniform float mid_point : hint_range(0.0, 1.0) = 0.5;               // Position of violet
uniform float contrast : hint_range(0.5, 2.0) = 1.0;

void fragment() {
    float angle_rad = radians(angle);
    vec2 dir = vec2(cos(angle_rad), sin(angle_rad));
    
    // Project UV onto direction to get linear position
    float pos = dot(UV - vec2(0.5), dir) + 0.5;
    pos = clamp(pos, 0.0, 1.0);
    
    // Apply contrast
    pos = pow(pos, contrast);
    
    // 3-Way Interpolation
    vec4 final_color;
    if (pos < mid_point) {
        // Interpolate between Start and Mid
        float t = pos / mid_point;
        final_color = mix(color_start, color_mid, t);
    } else {
        // Interpolate between Mid and End
        float t = (pos - mid_point) / (1.0 - mid_point);
        final_color = mix(color_mid, color_end, t);
    }
    
    COLOR = final_color;
}
