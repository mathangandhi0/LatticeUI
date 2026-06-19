extends VBoxContainer

var label_hour: Label
var label_min: Label
var label_ampm: Label

func _ready():
	# Configure VBox
	alignment = BoxContainer.ALIGNMENT_CENTER
	# Standardize width (approx drawer width) and sufficient height
	custom_minimum_size = Vector2(250, 250) 
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", -20) # tight packing
	
	# Hour Label (with gradient-like effect using modulate)
	label_hour = Label.new()
	label_hour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_hour.add_theme_font_size_override("font_size", 100)
	label_hour.add_theme_color_override("font_color", Color.WHITE)
	# Enhanced shadow for depth
	label_hour.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label_hour.add_theme_constant_override("shadow_offset_x", 3)
	label_hour.add_theme_constant_override("shadow_offset_y", 3)
	# Subtle outline for premium look
	label_hour.add_theme_color_override("font_outline_color", Color(0.4, 0.6, 1.0, 0.3))
	label_hour.add_theme_constant_override("outline_size", 2)
	add_child(label_hour)
	
	# Minute Label (slightly different color for visual hierarchy)
	label_min = Label.new()
	label_min.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_min.add_theme_font_size_override("font_size", 100)
	label_min.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))  # Slight blue tint
	# Enhanced shadow
	label_min.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label_min.add_theme_constant_override("shadow_offset_x", 3)
	label_min.add_theme_constant_override("shadow_offset_y", 3)
	# Subtle outline
	label_min.add_theme_color_override("font_outline_color", Color(0.4, 0.6, 1.0, 0.3))
	label_min.add_theme_constant_override("outline_size", 2)
	add_child(label_min)
	
	# AM/PM Label (accent color)
	label_ampm = Label.new()
	label_ampm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_ampm.add_theme_font_size_override("font_size", 50)
	label_ampm.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))  # Light blue
	# Shadow for readability
	label_ampm.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label_ampm.add_theme_constant_override("shadow_offset_x", 2)
	label_ampm.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label_ampm)
	
	update_time()
	
	# Timer for updates (1 second)
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(update_time)
	add_child(timer)
	timer.start()

var last_minute = -1  # Track minute changes for animation

func update_time():
	var time = Time.get_time_dict_from_system()
	var hour = time.hour
	var minute = time.minute
	
	var ampm = "AM"
	if hour >= 12:
		ampm = "PM"
	
	if hour > 12:
		hour -= 12
	if hour == 0:
		hour = 12
		
	label_hour.text = "%02d" % hour
	
	# Smooth fade transition when minute changes
	if minute != last_minute and last_minute != -1:
		var fade_tween = create_tween()
		fade_tween.set_parallel(true)
		fade_tween.tween_property(label_min, "modulate:a", 0.5, 0.15)
		fade_tween.tween_callback(func(): label_min.text = "%02d" % minute)
		fade_tween.tween_property(label_min, "modulate:a", 1.0, 0.15)
	else:
		label_min.text = "%02d" % minute
	
	last_minute = minute
	label_ampm.text = ampm
