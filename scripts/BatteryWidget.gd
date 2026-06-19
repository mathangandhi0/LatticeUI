extends VBoxContainer

var bar_bg: Panel
var bar_fill: ColorRect
var label_val: Label
var charge_dot: Panel
var _max_width: float = 0.0

func _ready():
	# FORCE MAXIMUM BRIGHTNESS (Alpha 1.0)
	modulate = Color(1, 1, 1, 1)
	
	# Configure VBox
	alignment = BoxContainer.ALIGNMENT_BEGIN 
	custom_minimum_size = Vector2(100, 95) # Reduced width for fitment
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 2)
	
	# 1. Spacer (Lowers the widget, no divider line)
	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 25) # Lowered "a little bit" as requested
	add_child(top_spacer)
	
	# 2. Main Bar Container - Edge to edge, no margins
	var bar_container = MarginContainer.new()
	bar_container.add_theme_constant_override("margin_left", 0)  # No margins
	bar_container.add_theme_constant_override("margin_right", 0)
	bar_container.add_theme_constant_override("margin_bottom", 0) 
	bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_container.custom_minimum_size = Vector2(0, 55)
	add_child(bar_container)
	
	# Border/Background (Edge to edge, no rounded corners)
	bar_bg = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 1.0) 
	style.border_width_left = 0  # No side borders
	style.border_width_top = 3
	style.border_width_right = 0  # No side borders
	style.border_width_bottom = 3
	style.border_color = Color(0.0, 0.7, 0.0, 1.0) 
	style.set_corner_radius_all(0)  # NO rounded corners
	bar_bg.add_theme_stylebox_override("panel", style)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Fill the card width
	bar_bg.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	bar_container.add_child(bar_bg)

	
	# Fill (OPAQUE NEON GREEN)
	bar_fill = ColorRect.new()
	bar_fill.color = Color(0.0, 0.6, 0.0, 1.0) 
	bar_fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar_fill.size_flags_horizontal = Control.SIZE_FILL 
	bar_bg.add_child(bar_fill)
	
	# Text Overlay (MAXIMUM READABILITY)
	label_val = Label.new()
	label_val.text = "--%"
	label_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_val.add_theme_font_size_override("font_size", 34)
	label_val.add_theme_color_override("font_color", Color.WHITE) 
	
	label_val.add_theme_color_override("font_outline_color", Color.BLACK)
	label_val.add_theme_constant_override("outline_size", 6)
	
	label_val.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(label_val)
	
	# Charging Dot (OPAQUE RED GLOW)
	var dot_panel = Panel.new()
	var dot_style = StyleBoxFlat.new()
	dot_style.bg_color = Color(1.0, 0.0, 0.0, 1.0) 
	dot_style.border_width_left = 2
	dot_style.border_width_top = 2
	dot_style.border_width_right = 2
	dot_style.border_width_bottom = 2
	dot_style.border_color = Color(1.0, 1.0, 1.0, 1.0) 
	dot_style.set_corner_radius_all(10)
	
	dot_style.shadow_color = Color(1.0, 0.0, 0.0, 1.0)
	dot_style.shadow_size = 10 
	
	dot_panel.add_theme_stylebox_override("panel", dot_style)
	dot_panel.custom_minimum_size = Vector2(18, 18)
	dot_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	dot_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dot_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -20)
	dot_panel.set_anchor_and_offset(SIDE_TOP, 0.5, -9)
	dot_panel.set_anchor_and_offset(SIDE_BOTTOM, 0.5, 9)
	charge_dot = dot_panel 
	bar_bg.add_child(charge_dot)
	
	bar_bg.resized.connect(_on_resize)
	update_battery()
	
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.autostart = true
	timer.timeout.connect(update_battery)
	add_child(timer)

func _on_resize():
	_max_width = bar_bg.size.x
	update_visuals()

var _last_percent = 0

func update_battery():
	var percent = -1
	var is_charging = false
	
	if Engine.has_singleton("AppLoader"):
		var loader = Engine.get_singleton("AppLoader")
		percent = loader.get_battery_level() 
		is_charging = loader.is_charging()
	
	if percent < 0:
		label_val.text = "PWR"
		_last_percent = 0
	else:
		label_val.text = str(percent) + "%"
		_last_percent = percent

	charge_dot.visible = is_charging
	update_visuals()

func update_visuals():
	if bar_bg.size.x > 0:
		_max_width = bar_bg.size.x
	if _max_width <= 0: return 
	var width = (_last_percent / 100.0) * _max_width
	bar_fill.size = Vector2(width, bar_bg.size.y)
