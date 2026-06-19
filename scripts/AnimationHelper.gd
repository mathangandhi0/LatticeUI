extends Node

# Animation Helper System for Lattice UI
# Provides reusable animation utilities for smooth, premium UI interactions

# ===== SCALE ANIMATIONS =====

# Bounce scale animation (press effect)
static func animate_bounce_scale(node: Node, from_scale: Vector2, to_scale: Vector2, duration: float = 0.15) -> Tween:
	var tween = node.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "scale", to_scale, duration)
	return tween

# Smooth scale animation
static func animate_scale(node: Node, to_scale: Vector2, duration: float = 0.2, ease: Tween.EaseType = Tween.EASE_OUT, trans: Tween.TransitionType = Tween.TRANS_QUART) -> Tween:
	var tween = node.create_tween()
	tween.set_ease(ease)
	tween.set_trans(trans)
	tween.tween_property(node, "scale", to_scale, duration)
	return tween

# Press and release animation sequence
static func animate_press_release(node: Node, press_scale: Vector2 = Vector2(0.92, 0.92), duration: float = 0.1) -> void:
	var tween = node.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(node, "scale", press_scale, duration)

static func animate_release(node: Node, normal_scale: Vector2 = Vector2(1.0, 1.0), duration: float = 0.15) -> void:
	var tween = node.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "scale", normal_scale, duration)

# ===== FADE ANIMATIONS =====

# Fade in animation
static func fade_in(node: CanvasItem, duration: float = 0.3, delay: float = 0.0) -> Tween:
	node.modulate.a = 0.0
	var tween = node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "modulate:a", 1.0, duration)
	return tween

# Fade out animation
static func fade_out(node: CanvasItem, duration: float = 0.3) -> Tween:
	var tween = node.create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "modulate:a", 0.0, duration)
	return tween

# Crossfade between two nodes
static func crossfade(node_out: CanvasItem, node_in: CanvasItem, duration: float = 0.3) -> void:
	fade_out(node_out, duration)
	fade_in(node_in, duration)

# ===== PULSE ANIMATIONS =====

# Continuous pulse animation (for glow effects)
static func pulse_continuous(node: CanvasItem, min_alpha: float = 0.3, max_alpha: float = 1.0, duration: float = 1.5) -> Tween:
	var tween = node.create_tween()
	tween.set_loops()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "modulate:a", max_alpha, duration / 2.0)
	tween.tween_property(node, "modulate:a", min_alpha, duration / 2.0)
	return tween

# Single pulse animation
static func pulse_once(node: CanvasItem, scale_amount: float = 1.1, duration: float = 0.3) -> Tween:
	var original_scale = node.scale
	var tween = node.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(node, "scale", original_scale * scale_amount, duration / 2.0)
	tween.tween_property(node, "scale", original_scale, duration / 2.0)
	return tween

# ===== GLOW ANIMATIONS =====

# Animate glow intensity (for ColorRect or similar)
static func animate_glow(node: CanvasItem, from_alpha: float, to_alpha: float, duration: float = 0.2) -> Tween:
	var tween = node.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(node, "modulate:a", to_alpha, duration)
	return tween

# Glow pulse (one cycle)
static func glow_pulse(node: CanvasItem, peak_alpha: float = 0.8, duration: float = 0.4) -> Tween:
	var original_alpha = node.modulate.a
	var tween = node.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "modulate:a", peak_alpha, duration / 2.0)
	tween.tween_property(node, "modulate:a", original_alpha, duration / 2.0)
	return tween

# ===== POSITION ANIMATIONS =====

# Slide in from direction
static func slide_in(node: Control, from_offset: Vector2, duration: float = 0.3, delay: float = 0.0) -> Tween:
	var original_pos = node.position
	node.position = original_pos + from_offset
	var tween = node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUART)
	tween.tween_property(node, "position", original_pos, duration)
	return tween

# Slide out to direction
static func slide_out(node: Control, to_offset: Vector2, duration: float = 0.3) -> Tween:
	var target_pos = node.position + to_offset
	var tween = node.create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUART)
	tween.tween_property(node, "position", target_pos, duration)
	return tween

# ===== ROTATION ANIMATIONS =====

# Rotate animation
static func rotate_to(node: Node2D, target_rotation: float, duration: float = 0.3) -> Tween:
	var tween = node.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "rotation", target_rotation, duration)
	return tween

# Spin animation (continuous)
static func spin_continuous(node: Node2D, speed: float = 1.0) -> Tween:
	var tween = node.create_tween()
	tween.set_loops()
	tween.tween_property(node, "rotation", TAU, 2.0 / speed)
	return tween

# ===== COMBINED EFFECTS =====

# Pop-in effect (scale + fade)
static func pop_in(node: CanvasItem, duration: float = 0.3, delay: float = 0.0) -> void:
	node.scale = Vector2(0.5, 0.5)
	node.modulate.a = 0.0
	
	var tween = node.create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "scale", Vector2(1.0, 1.0), duration)
	tween.tween_property(node, "modulate:a", 1.0, duration)

# Pop-out effect (scale + fade)
static func pop_out(node: CanvasItem, duration: float = 0.2) -> void:
	var tween = node.create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(node, "scale", Vector2(0.5, 0.5), duration)
	tween.tween_property(node, "modulate:a", 0.0, duration)
