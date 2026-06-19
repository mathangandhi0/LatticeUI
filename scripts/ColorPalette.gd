extends Node

# Premium Color Palette System for Lattice UI
# Provides vibrant, harmonious colors and gradients for modern UI design

# ===== PRIMARY GRADIENTS =====
# Deep Blue → Purple gradient for main UI elements
const PRIMARY_START = Color(0.15, 0.25, 0.45, 1.0)  # Deep Blue
const PRIMARY_END = Color(0.35, 0.15, 0.55, 1.0)    # Purple

# Lighter variant for highlights
const PRIMARY_LIGHT_START = Color(0.25, 0.35, 0.65, 1.0)
const PRIMARY_LIGHT_END = Color(0.45, 0.25, 0.75, 1.0)

# ===== ACCENT GRADIENTS =====
# Vibrant Orange → Pink for highlights and interactive elements
const ACCENT_START = Color(1.0, 0.5, 0.2, 1.0)      # Vibrant Orange
const ACCENT_END = Color(1.0, 0.3, 0.6, 1.0)        # Pink

# Cyan → Blue for alternative accents
const ACCENT_ALT_START = Color(0.2, 0.8, 1.0, 1.0)  # Cyan
const ACCENT_ALT_END = Color(0.4, 0.6, 1.0, 1.0)    # Blue

# ===== GLOW COLORS =====
const GLOW_PRIMARY = Color(0.4, 0.6, 1.0, 0.5)      # Blue Glow
const GLOW_ACCENT = Color(1.0, 0.6, 0.3, 0.5)       # Orange Glow
const GLOW_WHITE = Color(1.0, 1.0, 1.0, 0.3)        # White Glow

# ===== TEXT COLORS =====
const TEXT_PRIMARY = Color(1.0, 1.0, 1.0, 1.0)      # White
const TEXT_SECONDARY = Color(0.85, 0.85, 0.85, 1.0) # Light Gray
const TEXT_TERTIARY = Color(0.6, 0.6, 0.6, 1.0)     # Medium Gray

# ===== BACKGROUND COLORS =====
const BG_DARK = Color(0.05, 0.05, 0.1, 1.0)         # Very Dark Blue
const BG_MEDIUM = Color(0.1, 0.1, 0.2, 1.0)         # Dark Blue
const BG_GLASS = Color(0.05, 0.1, 0.25, 0.7)        # Glassmorphism Background

# ===== HELPER FUNCTIONS =====

# Get a gradient between two colors
static func get_gradient(start: Color, end: Color) -> Gradient:
	var grad = Gradient.new()
	grad.set_color(0, start)
	grad.set_color(1, end)
	return grad

# Get primary gradient
static func get_primary_gradient() -> Gradient:
	return get_gradient(PRIMARY_START, PRIMARY_END)

# Get accent gradient
static func get_accent_gradient() -> Gradient:
	return get_gradient(ACCENT_START, ACCENT_END)

# Get alternative accent gradient
static func get_accent_alt_gradient() -> Gradient:
	return get_gradient(ACCENT_ALT_START, ACCENT_ALT_END)

# Interpolate between two colors
static func lerp_color(from: Color, to: Color, weight: float) -> Color:
	return from.lerp(to, weight)

# Get primary color at specific position (0.0 to 1.0)
static func get_primary_at(position: float) -> Color:
	return lerp_color(PRIMARY_START, PRIMARY_END, position)

# Get accent color at specific position (0.0 to 1.0)
static func get_accent_at(position: float) -> Color:
	return lerp_color(ACCENT_START, ACCENT_END, position)

# Create a GradientTexture2D for use in shaders/materials
static func create_gradient_texture(start: Color, end: Color, vertical: bool = true) -> GradientTexture2D:
	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = get_gradient(start, end)
	
	if vertical:
		grad_tex.fill_from = Vector2(0.5, 0.0)
		grad_tex.fill_to = Vector2(0.5, 1.0)
	else:
		grad_tex.fill_from = Vector2(0.0, 0.5)
		grad_tex.fill_to = Vector2(1.0, 0.5)
	
	return grad_tex

# Create primary gradient texture
static func create_primary_gradient_texture(vertical: bool = true) -> GradientTexture2D:
	return create_gradient_texture(PRIMARY_START, PRIMARY_END, vertical)

# Create accent gradient texture
static func create_accent_gradient_texture(vertical: bool = true) -> GradientTexture2D:
	return create_gradient_texture(ACCENT_START, ACCENT_END, vertical)
