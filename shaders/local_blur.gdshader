shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 5.0) = 2.0;
uniform vec4 glass_tint : source_color = vec4(1.0, 1.0, 1.0, 0.05);

void fragment() {
    vec4 color = vec4(0.0);
    float total = 0.0;
    
    // Very simple 3x3 sample for maximum compatibility
    for (float x = -1.0; x <= 1.0; x++) {
        for (float y = -1.0; y <= 1.0; y++) {
            vec2 offset = vec2(x, y) * blur_amount * 0.01;
            color += texture(TEXTURE, UV + offset);
            total += 1.0;
        }
    }
    color /= total;
    color.rgb = mix(color.rgb, glass_tint.rgb, glass_tint.a);
    COLOR = color;
}
