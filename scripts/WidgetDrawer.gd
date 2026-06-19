extends Control

# --- CONFIG ---
const SLOT_COUNT = 4
const SNAP_DURATION = 0.2
var slot_width = 0.0

# --- PEEK & EXPAND STATE ---
var is_expanded = false
var collapse_timer: Timer
var touch_down_time = 0
var just_expanded_on_touch_down = false

# --- STATE ---
var current_slot = 0
var is_dragging = false
var drag_start_x = 0.0
var drawer_start_x = 0.0

# --- NODES ---
var background: ColorRect
var scroll_container: ScrollContainer
var widget_box: VBoxContainer

# --- PALETTES ---
const PALETTES = [
	{ "name": "Midnight", "start": Color(0.45, 0.1, 0.35, 1.0), "mid": Color(0.25, 0.1, 0.45, 1.0), "end": Color(0.05, 0.1, 0.25, 1.0) }, 
	{ "name": "Sunset", "start": Color(0.6, 0.2, 0.1, 1.0), "mid": Color(0.4, 0.1, 0.3, 1.0), "end": Color(0.1, 0.05, 0.2, 1.0) },
	{ "name": "Ocean", "start": Color(0.1, 0.5, 0.7, 1.0), "mid": Color(0.05, 0.3, 0.5, 1.0), "end": Color(0.02, 0.1, 0.3, 1.0) },
]

func _ready():
	z_index = 100 # Force on top
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Setup Collapse Timer for Peek & Expand
	collapse_timer = Timer.new()
	collapse_timer.one_shot = true
	collapse_timer.timeout.connect(collapse_drawer)
	add_child(collapse_timer)
	
	# V4.74: Root clip_contents MUST be off for borders to show at edges
	# Only BlurClip should have clip_contents = true.
	
	# 1. Setup Dimensions (Robustly)
	var screen_size = get_viewport_rect().size # Consistent with Main.gd
	if screen_size.y == 0: screen_size = DisplayServer.window_get_size() # Fallback
	
	# Start in Slim/Peek mode (1/8 screen width)
	slot_width = screen_size.x * 0.125
	var screen_width = screen_size.x
	
	# Set size of this drawer (1/8 width, full height + 20px safety margin)
	size = Vector2(slot_width, screen_size.y + 20)
	custom_minimum_size = size
	
	# Start at Right Extreme (Slot 0)
	position = Vector2(screen_width - slot_width, 0) 
	print("WidgetDrawer: Initializing. Screen: ", screen_size, " Pos: ", position, " Size: ", size)
	
	background = ColorRect.new()
	background.size = Vector2(size.x, size.y)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var shader = load("res://shaders/premium_gradient.gdshader")
	if shader:
		var mat = ShaderMaterial.new()
		mat.shader = shader
		background.material = mat
		apply_palette_index(Settings.current_config.get("drawer_palette_index", 0))
	else:
		background.color = Color(0.05, 0.1, 0.25, 0.6) 
		
	add_child(background)
	
	# 2. Glass Overlay Layer (Shaderless Technique)
	# V4.73: Wrap blur in its own clip container so root clip_contents stays OFF
	var clip_container = Control.new()
	clip_container.name = "BlurClip"
	clip_container.size = size # V14.55: Match drawer size
	clip_container.clip_contents = true
	clip_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip_container)
	move_child(clip_container, 1) # Just above background

	var blur_layer = TextureRect.new()
	blur_layer.name = "BlurLayer"
	blur_layer.texture = Settings.blurred_wallpaper_texture
	blur_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blur_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_container.add_child(blur_layer)
	blur_layer.modulate.a = 1.0 # Ensure full opacity
	
	# Dynamic Sync
	Settings.blurred_wallpaper_updated.connect(func():
		var blayer = get_node_or_null("BlurClip/BlurLayer")
		if blayer:
			# V4.76: Flicker Protection - Only fade if texture changed
			if blayer.texture == Settings.blurred_wallpaper_texture:
				return

			# V4.59: Smooth Fade-in Transition
			var tw = create_tween()
			blayer.modulate.a = 0
			blayer.texture = Settings.blurred_wallpaper_texture
			tw.tween_property(blayer, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	)
	
	# 3. Scroll Container (Vertical Scrolling for Widgets)
	scroll_container = ScrollContainer.new()
	# REACH ZERO GAP: Align exactly with Search Bar top edge (350px from bottom)
	scroll_container.size = Vector2(size.x, screen_size.y - 350)
	scroll_container.position = Vector2(0, 0)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.mouse_filter = Control.MOUSE_FILTER_PASS # Propagate to parent
	add_child(scroll_container)
	
	# 4. VBox for Widgets
	widget_box = VBoxContainer.new()
	widget_box.name = "WidgetBox"
	widget_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	widget_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	widget_box.mouse_filter = Control.MOUSE_FILTER_PASS 
	widget_box.add_theme_constant_override("separation", 10)
	scroll_container.add_child(widget_box)
	
	# Top Spacer (Status Bar) - increased for better spacing
	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30) 
	widget_box.add_child(top_spacer)
	
	# Middle Expander (Pushes Date to Bottom)
	# We need to add this *after* the Clock (which is added dynamically)
	# But wait, Main.gd adds the widgets. We can't control the order here easily if Main adds them.
	# Main.gd adds Clock, then Date.
	# We need to inject a spacer IN BETWEEN them.
	
	# Option: Expose a helper to add a spacer?
	# Or let Main.gd add the spacer?
	# Let's add a helper function "add_flexible_spacer()"
	
	# 5. Input Setup
	# STOP ensures we catch everything that passes through the children.
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# V4.73: Borders added LAST so they render on top of scroll_container
	var left_border = ColorRect.new()
	left_border.anchor_left   = 0.0; left_border.anchor_right  = 0.0
	left_border.anchor_top    = 0.0; left_border.anchor_bottom = 1.0
	left_border.offset_left   = 0;   left_border.offset_right  = 1
	left_border.offset_top    = 0;   left_border.offset_bottom = 0
	left_border.color = Color(1, 1, 1, 0.22)
	left_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_border.z_index = 1
	add_child(left_border)
	
	# V4.75: Enhanced Right Border visibility
	var right_border = ColorRect.new()
	right_border.anchor_left   = 1.0; right_border.anchor_right  = 1.0
	right_border.anchor_top    = 0.0; right_border.anchor_bottom = 1.0
	right_border.offset_left   = -2;  right_border.offset_right  = 0 # 2px wide
	right_border.offset_top    = 0;   right_border.offset_bottom = 0
	right_border.color = Color(1, 1, 1, 0.22)
	right_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_border.z_index = 2 # Definitely top
	add_child(right_border)
	
	print("WidgetDrawer: Initialized. Width: ", slot_width)

var last_tap_time = 0
const DOUBLE_TAP_DELAY = 400
var drag_start_y = 0.0  # For vertical swipe detection
const SWIPE_DOWN_THRESHOLD = 100  # Pixels needed for swipe-down gesture




func add_logo(texture: Texture2D):
	if not texture: return
	
	var logo_container = CenterContainer.new()
	logo_container.custom_minimum_size = Vector2(0, 140)
	logo_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logo_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var tex_rect = TextureRect.new()
	tex_rect.texture = texture
	tex_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Scale logo to fit well in the expanded drawer width (1/4 screen)
	var screen_w = get_viewport_rect().size.x
	if screen_w == 0: screen_w = DisplayServer.window_get_size().x
	var target_w = screen_w / 4.0
	tex_rect.custom_minimum_size = Vector2(target_w * 0.7, 100)
	logo_container.add_child(tex_rect)
	
	if widget_box: 
		widget_box.add_child(logo_container)

func add_spacer(height: int):
	var s = Control.new()
	s.custom_minimum_size = Vector2(0, height)
	s.mouse_filter = Control.MOUSE_FILTER_PASS # Crucial for parent gestures
	if widget_box: widget_box.add_child(s)

func add_expander():
	var s = Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_PASS # Crucial for parent gestures
	if widget_box: widget_box.add_child(s)

func add_widget(widget_node: Node):
	if widget_box:
		var wrapper = _wrap_widget(widget_node)
		widget_box.add_child(wrapper)
	else:
		print("WidgetDrawer: Warning - widget_box not ready used add_child directly on self (fallback) or deferred?")
		# Queue it? Or just force init?
		# Safest: wait for ready.
		call_deferred("deferred_add_widget", widget_node)

func deferred_add_widget(widget_node: Node):
	if widget_box:
		var wrapper = _wrap_widget(widget_node)
		widget_box.add_child(wrapper)
	else:
		print("WidgetDrawer: CRITICAL - widget_box list missing even after defer.")

func _wrap_widget(node: Node) -> MarginContainer:
	# 1. Outer Margin (Shelf Spacing)
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 0) 
	margin.add_theme_constant_override("margin_right", 0)
	
	# Determine if this is the Power Widget to remove its padding
	var is_power = false
	if node.has_method("update_battery"): is_power = true
	
	# 2. Panel Container
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.22)
	style.set_corner_radius_all(12)
	
	style.content_margin_left = 0 if is_power else 8
	style.content_margin_top = 15
	style.content_margin_right = 0 if is_power else 8
	style.content_margin_bottom = 15
	
	panel.add_theme_stylebox_override("panel", style)
	
	# 3. Add Content
	panel.add_child(node)
	margin.add_child(panel)
	
	return margin

var _drag_timer = 0.0
var _long_press_triggered = false
const LONG_PRESS_THRESHOLD = 0.8 # 800ms for background cycle (buffer for widgets)

func cancel_gestures():
	print("WidgetDrawer: Gestures CANCELLED by child widget")
	is_dragging = false
	_drag_timer = 0.0
	_long_press_triggered = false

func _process(delta):
	# V4.45: SHADERLESS ALIGNMENT (Merged)
	var blayer = get_node_or_null("BlurClip/BlurLayer")
	if blayer:
		blayer.global_position = Vector2.ZERO
		blayer.size = get_viewport_rect().size

	# Fail-safe: if a menu is open, force kill any ongoing drag/long-press
	if is_dragging and _is_modal_active():
		is_dragging = false
		_drag_timer = 0.0
		return

	if is_dragging and not _long_press_triggered:
		_drag_timer += delta
		# print("WidgetDrawer: Drag timer: ", _drag_timer)
		if _drag_timer > LONG_PRESS_THRESHOLD:
			print("WidgetDrawer: ACTION -> Long Press Triggered!")
			_long_press_triggered = true
			cycle_palette()    # Update colors
	elif not is_dragging:
		_drag_timer = 0.0

func cycle_palette():
	var current_idx = int(Settings.current_config.get("drawer_palette_index", 0))
	var next_idx = (current_idx + 1) % PALETTES.size()
	
	print("WidgetDrawer: Cycling palette to ", PALETTES[next_idx]["name"])
	apply_palette_index(next_idx)
	
	# Persist
	Settings.current_config["drawer_palette_index"] = next_idx
	Settings.save_config()
	
	# Feedback
	if Engine.has_singleton("AppLoader"):
		Engine.get_singleton("AppLoader").vibrate(50)

func apply_palette_index(idx: int):
	if idx < 0 or idx >= PALETTES.size(): idx = 0
	var p = PALETTES[idx]
	if background and background.material:
		var mat = background.material as ShaderMaterial
		mat.set_shader_parameter("color_start", Color(p["start"].r, p["start"].g, p["start"].b, 0.4))
		mat.set_shader_parameter("color_mid", Color(p["mid"].r, p["mid"].g, p["mid"].b, 0.2))
		mat.set_shader_parameter("color_end", Color(p["end"].r, p["end"].g, p["end"].b, 0.5))
		mat.set_shader_parameter("angle", 135.0)

func _input(event):
	if not visible: return
	
	# V14.33: STRICT MULTI-TOUCH BLOCK
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if event.index > 0: return
		
	# GLOBAL GESTURE DETECTION (Double Tap, Long Press, Paging)
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# DOUBLE-SAFETY GUARD:
		# Check for the literal existence of active overlay menus.
		# This is 100% reliable even if 'hovered_control' is null.
		if _is_modal_active():
			return

	if event is InputEventScreenTouch:
		var rect = get_global_rect()
		var is_inside = rect.has_point(event.position)
		
		if not is_inside:
			if event.pressed and is_expanded:
				collapse_drawer()
			if not is_dragging:
				return
		
		if event.pressed:
			# Track touch down for gesture duration
			touch_down_time = Time.get_ticks_msec()
			
			# 1. Double Tap Detection
			var now = Time.get_ticks_msec()
			if now - last_tap_time < 400:
				print("WidgetDrawer: ACTION -> Double Tap Detected")
				if Engine.has_singleton("AppLoader"):
					var app_loader = Engine.get_singleton("AppLoader")
					app_loader.lock_screen()
				last_tap_time = 0 
			else:
				last_tap_time = now
			
			# 2. Track for Gestures
			is_dragging = true
			_drag_timer = 0.0
			_long_press_triggered = false
			drag_start_x = event.position.x
			drag_start_y = event.position.y 
			drawer_start_x = position.x
		else:
			# Touch release (pressed == false)
			var dist = event.position.distance_to(Vector2(drag_start_x, drag_start_y))
			var duration = Time.get_ticks_msec() - touch_down_time
			var is_tap = (dist < 50.0 and duration < 400)
			
			if is_dragging and not is_tap:
				finish_drag()
			
			is_dragging = false
			
			if is_tap:
				# Tapping toggles the drawer state
				if is_expanded:
					collapse_drawer()
				else:
					expand_drawer()
					
			_drag_timer = 0.0
			_long_press_triggered = false
			
	elif event is InputEventScreenDrag and is_dragging:
		var delta_x = event.position.x - drag_start_x
		var delta_y = event.position.y - drag_start_y
		
		# If collapsed, expand the drawer if the user drags left (pulling it out)
		if not is_expanded and delta_x < -20.0 and abs(delta_x) > abs(delta_y):
			expand_drawer()
			var screen_w = get_viewport_rect().size.x
			if screen_w == 0: screen_w = DisplayServer.window_get_size().x
			var full_width = screen_w / 4.0
			drawer_start_x = screen_w - full_width
		
		# ONLY move visually if Dynamic Positioning is ON and it is expanded
		if is_expanded and Settings.current_config.get("dynamic_widget_position", true):
			var global_x = event.position.x
			var delta = global_x - drag_start_x
			# Move/Clamp visually
			position.x = clamp(drawer_start_x + delta, 0.0, get_viewport_rect().size.x - slot_width)

func _gui_input(event):
	# V14.33: STRICT MULTI-TOUCH BLOCK
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if event.index > 0: return
		
	pass

func _on_background_input(event):
	pass

func _handle_gestures(event):
	pass

func finish_drag():
	var current_pos = get_global_mouse_position()
	var delta_y = current_pos.y - drag_start_y
	var delta_x = current_pos.x - drag_start_x
	
	if delta_y > SWIPE_DOWN_THRESHOLD and delta_y > abs(delta_x) * 1.5:
		print("WidgetDrawer: Swipe Down Detected -> Opening Notifications")
		if Engine.has_singleton("AppLoader"):
			Engine.get_singleton("AppLoader").expand_notifications()
		if not Settings.current_config.get("dynamic_widget_position", true): return

	if Settings.current_config.get("dynamic_widget_position", true):
		var screen_width = get_viewport_rect().size.x
		var max_x = screen_width - slot_width
		var dist_from_right = max_x - position.x
		var target_index = round(dist_from_right / slot_width)
		snap_to_slot(int(target_index))
	else:
		snap_to_slot(current_slot)
		
	# Start collapse timer since drag finished
	collapse_timer.start(4.0)

func expand_drawer():
	collapse_timer.start(4.0)
	if is_expanded: return
	
	is_expanded = true
	var screen_w = get_viewport_rect().size.x
	if screen_w == 0: screen_w = DisplayServer.window_get_size().x
	animate_width_to(screen_w / 4.0)

func collapse_drawer():
	if is_dragging:
		collapse_timer.start(2.0)
		return
	
	is_expanded = false
	var screen_w = get_viewport_rect().size.x
	if screen_w == 0: screen_w = DisplayServer.window_get_size().x
	animate_width_to(screen_w * 0.125)

func animate_width_to(target_w: float):
	var tween = create_tween()
	tween.tween_method(set_drawer_width, slot_width, target_w, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func set_drawer_width(w: float):
	slot_width = w
	size.x = w
	custom_minimum_size.x = w
	if background:
		background.size.x = w
	var clip = get_node_or_null("BlurClip")
	if clip:
		clip.size.x = w
	if scroll_container:
		scroll_container.size.x = w
	
	var screen_width = get_viewport_rect().size.x
	if screen_width == 0: screen_width = DisplayServer.window_get_size().x
	position.x = (screen_width - w) - (current_slot * w)

func set_page_index(index: int):
	# Page 0 (Home) -> Visible, Slot 0 (Right)
	# Page 1 (Drawer) -> Hidden
	visible = (index == 0)
	if visible:
		collapse_drawer()
		snap_to_slot(0)
	else:
		is_dragging = false

func snap_to_slot(index: int):
	current_slot = index
	# Clamp index to available slots (0=Right, 3=Left)
	if current_slot < 0: current_slot = 0
	if current_slot >= SLOT_COUNT: current_slot = SLOT_COUNT - 1
	
	var screen_width = get_viewport_rect().size.x
	# Slot indices: 0 = extreme right, 1 = slightly left, ..., 3 = extreme left
	var target_x = (screen_width - slot_width) - (current_slot * slot_width)
	
	var tween = create_tween()
	tween.tween_property(self, "position:x", target_x, SNAP_DURATION).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	# Trigger theme feedback?
	if target_x < screen_width:
		pass
	
	print("WidgetDrawer: Snapped to slot ", current_slot, " (x=", target_x, ")")

	print("WidgetDrawer: Process Finished.")

func _is_modal_active() -> bool:
	var root = get_tree().root
	# 1. Check for Settings (it only exists in tree when open)
	if root.has_node("Main/SettingsCanvas"):
		return true
	
	# 2. Check for Search (might exist but be hidden)
	var search = root.get_node_or_null("Main/SearchLayer")
	if search:
		for child in search.get_children():
			if child is Control and child.is_visible_in_tree():
				return true
	
	# 3. Check for high-layer popups (WeatherSettings, etc)
	for child in root.get_children():
		if child is CanvasLayer and child.layer >= 120:
			return true
	
	return false
