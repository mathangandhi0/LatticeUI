shader_type canvas_item;

uniform int shape_id = 0; // 0=Circle, 1=Squircle, 2=RoundedSquare, 3=Teardrop, 4=Message, 5=Square
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float size = 1.0;

// SDF Functions
float sdCircle(vec2 p, float r) {
    return length(p) - r;
}

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdRoundedBox(vec2 p, vec2 b, vec4 r) {
    vec4 rad = r;
    rad.xy = (p.x > 0.0) ? rad.xy : rad.zw;
    rad.x  = (p.y > 0.0) ? rad.x  : rad.y;
    vec2 q = abs(p) - b + rad.x;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - rad.x;
}

// Superellipse (Squircle-ish)
float sdSquircle(vec2 p, float b, float n) {
    return pow(pow(abs(p.x), n) + pow(abs(p.y), n), 1.0/n) - b;
}

// Teardrop (Circle with a tail) - approximated by blending 
float sdTeardrop(vec2 p, float r) {
    // This is a stylistic teardrop: generally a circle but pulled at bottom-left? 
    // Android Teardrop is usually symmetrical or bottom-right.
    // Let's model it as a rounded box with one sharp corner, but SMOOTH.
    // Actually, SDF for a teardrop is complex. 
    // Let's use a mix of Circle and a corner point.
    
    // Simpler approach for "Android Teardrop":
    // It's mostly a squircle/circle but one corner is 0 radius.
    // But we need the sides to be straight(ish) approaching the corner?
    // Let's stick to the RoundedBox with non-uniform radius for now, 
    // BUT we must implement it via SDF to get antialiasing and smoothness.
    
    // Radius values: top-left, top-right, bottom-right, bottom-left
    // Android Teardrop (usually): Top-Left, Top-Right, Bottom-Left are rounded. Bottom-Right is sharp?
    // Or Bottom-Left is sharp?
    // Let's assume Bottom-Left is sharp for "Waterdrop" style.
    
    // However, the shader sdRoundedBox above handles non-uniform if we expand it.
    // Standard SDF lib usually has uniform radius.
    return 0.0;
}

// Standardized: vec4 r = (TopLeft, TopRight, BottomRight, BottomLeft)
float sdRoundedBoxNonUniform(vec2 p, vec2 b, vec4 r) {
    vec4 rad = r;
    // p.x > 0 (Right) -> TR (r.y), BR (r.z)
    // p.x < 0 (Left)  -> TL (r.x), BL (r.w)
    vec2 corners_x = (p.x > 0.0) ? rad.yz : rad.xw;
    
    // p.y > 0 (Bottom) -> Select 2nd component of corners_x (BR or BL)
    // p.y < 0 (Top)    -> Select 1st component of corners_x (TR or TL)
    float corner_r = (p.y > 0.0) ? corners_x.y : corners_x.x;
    
    vec2 q = abs(p) - b + corner_r;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - corner_r;
}

void fragment() {
    vec2 uv = UV - 0.5;
    float d = 0.0;
    
    if (shape_id == 0) { // Circle
        d = sdCircle(uv, 0.5);
    } else if (shape_id == 1) { // Squircle (Superellipse n=4)
        // Android Squircle is close to n=4
        d = pow(pow(abs(uv.x), 4.0) + pow(abs(uv.y), 4.0), 1.0/4.0) - 0.5;
    } else if (shape_id == 2) { // Rounded Square (Radius ~20%)
        d = sdRoundedBoxNonUniform(uv, vec2(0.5), vec4(0.15));
    } else if (shape_id == 3) { // Teardrop
        // Android Teardrop is usually a circle with a tangent straight line to the corner?
        // Actually, it's often defined as a full circle blended with a square corner?
        // Let's try a hybrid: 
        // A circle at center, combined with a square in one quadrant?
        // No, the standard Android Teardrop (bottom-left sharp) is:
        // Top-Right, Top-Left, Bottom-Right are rounded (radius 50%).
        // Bottom-Left is sharp (radius 0).
        // But the sides are STRAIGHT connecting the curves?
        // My previous SDF was correct for "RoundedBox with 3 rounded corners".
        // If it looks "different", maybe the radius is LARGER?
        // Android icons are 108dp. Mask is 100x100 path, usually centered.
        // The safe zone is circle 66dp.
        
        // Let's try a slightly larger radius for the rounded parts.
        // If box is 1.0 size (0.5 extent), max radius is 0.5.
        // Maybe the user wants the "Waterdrop" style (bottom-right sharp)?
        // Or "Teardrop" (bottom-left sharp)?
        // I will stick to TL/TR/BR/BL logic.
        
        // Refined Teardrop (Bottom Left Sharp -> typical "Teardrop")
        // Radius: 0.5 (Full Round) for others.
        d = sdRoundedBoxNonUniform(uv, vec2(0.5), vec4(0.5, 0.5, 0.5, 0.05)); 
        // 0.05 radius on the "sharp" corner makes it slightly friendlier/closer to some implementations? 
        // Or strictly 0.0? Use 0.0 for now, but ensure the OTHER radii are full 0.5.
    } else if (shape_id == 4) { // Message (Bottom Right Sharp)
        d = sdRoundedBoxNonUniform(uv, vec2(0.5), vec4(0.5, 0.5, 0.0, 0.5));
    } else if (shape_id == 5) { // Square
        d = sdBox(uv, vec2(0.5));
    } else if (shape_id == 6) { // Pebble
        d = sdRoundedBoxNonUniform(uv, vec2(0.5), vec4(0.35));
    } else {
        d = sdCircle(uv, 0.5);
    }

    // Antialiasing
    // Smoothstep for 0.0 cutoff.
    // Screen-space derivative or fixed width?
    float w = fwidth(d);
    float alpha = 1.0 - smoothstep(-w, w, d);
    
    // Outline / Shadow could be added here
    
    COLOR = vec4(color.rgb, color.a * alpha);
}
