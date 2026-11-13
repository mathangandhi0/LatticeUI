extends Control

signal config_changed(key, value)
signal closing

func close_settings():
	emit_signal("closing")
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
	tween.finished.connect(func(): queue_free())

func _ready():
	print("!!! SettingsUI: _ready() START !!!")
	
	# Premium Fade In (Increased to 0.5s)
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	
	# Visual/Window Setup
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # Ensure it fills screen
	setup_ui()
	print("!!! SettingsUI: _ready() COMPLETE !!!")

func setup_ui():
	print("SettingsUI: Building UI...")
	var screen_size = get_viewport_rect().size
	
	# 1. Blurred Background Layer (Frosted Glass Effect)
	var bg = TextureRect.new()
	bg.texture = Settings.blurred_wallpaper_texture
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.size = screen_size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP # STOP propagation immediately
	add_child(bg)
	
	# 2. Readability Overlay (Darken for text clarity)
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.4) # 40% dark tint
	overlay.size = screen_size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	
	# USER REQUEST: Transparent (1% opaque) full screen panel to block input
	# Added at low index to be behind actual settings but cover everything.
	var blocker = ColorRect.new()
	blocker.name = "InputShield"
	blocker.color = Color(0, 0, 0, 0.01) # 1% opacity
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	
	# Main Container with padding for status bar
	var main_vbox = VBoxContainer.new()
	main_vbox.size = Vector2(screen_size.x, screen_size.y)
	main_vbox.position = Vector2(0, 0)
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)
	
	var create_pill_toggle = func(parent, text, key):
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 20)
		hbox.custom_minimum_size = Vector2(0, 100) # Slightly reduced height
		
		var label = Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", 45)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)
		
		# The Pill Switch Container
		var switch = Control.new()
		switch.custom_minimum_size = Vector2(140, 60) # User: 140x60
		switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(switch)
		
		# Pill Background
		var bg_style = StyleBoxFlat.new()
		bg_style.corner_radius_top_left = 30 # Half height
		bg_style.corner_radius_top_right = 30
		bg_style.corner_radius_bottom_left = 30
		bg_style.corner_radius_bottom_right = 30
		
		var bg_panel = Panel.new()
		bg_panel.size = Vector2(140, 60)
		bg_panel.add_theme_stylebox_override("panel", bg_style)
		switch.add_child(bg_panel)
		
		# Knob (Circle)
		var knob_style = StyleBoxFlat.new()
		knob_style.corner_radius_top_left = 25 # Half size
		knob_style.corner_radius_top_right = 25
		knob_style.corner_radius_bottom_left = 25
		knob_style.corner_radius_bottom_right = 25
		knob_style.bg_color = Color.WHITE
		knob_style.shadow_size = 4
		knob_style.shadow_color = Color(0, 0, 0, 0.3)
		
		var knob = Panel.new()
		knob.size = Vector2(50, 50) # User: 50x50
		knob.position = Vector2(5, 5) # Margin 5
		knob.add_theme_stylebox_override("panel", knob_style)
		switch.add_child(knob)
		
		var update_ui = func(instant=false):
			var active = Settings.current_config.get(key, false)
			# Calculation: 140 (width) - 50 (knob) - 5 (margin) = 85
			var target_x = 85 if active else 5
			var target_color = Color(0.2, 0.7, 0.4) if active else Color(0.2, 0.2, 0.25)
			
			if instant:
				knob.position.x = target_x
				bg_style.bg_color = target_color
			else:
				var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tween.tween_property(knob, "position:x", target_x, 0.2)
				tween.tween_property(bg_style, "bg_color", target_color, 0.2)
		
		update_ui.call(true)
		
		# Interaction
		var trigger = Button.new()
		trigger.flat = true
		trigger.size = Vector2(140, 60)
		trigger.mouse_filter = Control.MOUSE_FILTER_PASS
		switch.add_child(trigger)
		
		trigger.pressed.connect(func():
			var new_val = !Settings.current_config.get(key, false)
			Settings.current_config[key] = new_val
			update_ui.call()
			emit_signal("config_changed", key, new_val)
			Settings.save_config() # Auto-Save
		)
		
		parent.add_child(hbox)
	
	# Status Bar Spacer
	var status_spacer = Control.new()
	status_spacer.custom_minimum_size = Vector2(0, 80)
	main_vbox.add_child(status_spacer)
	
	# Title (Floating directly over the blurred root, bypassing VBox container themes)
	var title = Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 110)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.custom_minimum_size = Vector2(0, 220)
	title.position = Vector2(0, 80) # Push down below status bar spacer
	add_child(title) # Add directly to root!
	
	# Empty spacer in the VBox to leave room for the floating title
	var head_spacer = Control.new()
	head_spacer.custom_minimum_size = Vector2(0, 220)
	main_vbox.add_child(head_spacer)
	
	# Close Button (Top Right)
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 80)
	close_btn.custom_minimum_size = Vector2(160, 160)
	close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close_btn.position = Vector2(screen_size.x - 180, 20)
	close_btn.pressed.connect(func(): queue_free())
	add_child(close_btn)
	
	# Scrollable Area
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 70) # Increased from 40 for more air
	
	# 2. Adjust margin (No footer)
	var outer_margin = 40
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", outer_margin)
	margin_container.add_theme_constant_override("margin_right", outer_margin)
	margin_container.add_theme_constant_override("margin_top", 20)
	margin_container.add_theme_constant_override("margin_bottom", 120) # Space for nav bar
	margin_container.add_child(list)
	scroll.add_child(margin_container)
	
	# --- SECTIONS ---
	
	# Section: Visuals
	var visuals_box = create_grouped_box(list, "Visuals")
	
	# Item: System Settings
	var sys_item = create_settings_item(visuals_box, "System Settings", "Configure theme, wallpaper, and system icons")
	
	var sys_btn = Button.new()
	sys_btn.text = "Set Wallpaper"
	sys_btn.custom_minimum_size = Vector2(0, 110)
	sys_btn.add_theme_font_size_override("font_size", 45) # Match Dropdown
	sys_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# Glass Style for Buttons
	var glass_style = StyleBoxFlat.new()
	glass_style.bg_color = Color(1, 1, 1, 0.1)
	glass_style.border_width_left = 1
	glass_style.border_width_top = 1
	glass_style.border_width_right = 1
	glass_style.border_width_bottom = 1
	glass_style.border_color = Color(1, 1, 1, 0.15)
	glass_style.set_corner_radius_all(30)
	glass_style.content_margin_left = 40
	
	sys_btn.add_theme_stylebox_override("normal", glass_style)
	sys_btn.add_theme_stylebox_override("pressed", glass_style)
	sys_btn.add_theme_stylebox_override("hover", glass_style)
	
	sys_btn.pressed.connect(func():
		_on_wallpaper_btn_pressed(sys_btn)
	)
	
	sys_item.add_child(sys_btn)
	
	# Item: Icon Packs (REFACTORED: Dropdown for better reliability)
	var pack_item = create_settings_item(visuals_box, "Icon Pack", "Choose an installed theme")
	
	var pack_options = OptionButton.new()
	pack_options.custom_minimum_size = Vector2(0, 140) # Spacious height
	pack_options.add_theme_font_size_override("font_size", 45)
	pack_options.clip_text = true
	
	pack_options.add_theme_stylebox_override("normal", glass_style)
	pack_options.add_theme_stylebox_override("hover", glass_style)
	pack_options.add_theme_stylebox_override("pressed", glass_style)
	
	# Increase spacing in the popup list
	var popup = pack_options.get_popup()
	popup.add_theme_constant_override("v_separation", 35)
	popup.add_theme_font_size_override("font_size", 45)
	
	pack_item.add_child(pack_options)
	
	# Populate Options
	var pack_list_data = [] # Track data by index
	
	# 1. System Default
	pack_options.add_item("System Default")
	pack_list_data.append("") # Empty pkg for system
	
	# 2. Installed Packs
	if Engine.has_singleton("AppLoader"):
		var json_str = Engine.get_singleton("AppLoader").get_installed_icon_packs()
		var json = JSON.new()
		if json.parse(json_str) == OK:
			var packs = json.data
			for p in packs:
				pack_options.add_item(p.get("name", "Pack"))
				pack_list_data.append(p.get("pkg", ""))
	
	var cur_pkg = Settings.current_config.get("active_icon_pack", "")
	for i in range(pack_list_data.size()):
		if pack_list_data[i] == cur_pkg:
			pack_options.selected = i
			break
			
	var shape_item = create_settings_item(visuals_box, "Icon Shape", "Define the shape for system icons")
	
	pack_options.item_selected.connect(func(index):
		var pkg = pack_list_data[index]
		if Engine.has_singleton("AppLoader"):
			Engine.get_singleton("AppLoader").vibrate(40)
		
		Settings.clear_texture_cache() # V4.74: Clear cache to force refresh
		Settings.current_config.active_icon_pack = pkg
		Settings.save_config()
		
		# Conditional visibility for Icon Shape: Only show if pkg is empty (System Default)
		shape_item.visible = (pkg == "")
		
		if Engine.has_singleton("AppLoader"):
			print("SettingsUI: Force activating JNI icon pack: ", pkg)
			Engine.get_singleton("AppLoader").set_active_icon_pack(pkg)
			
		emit_signal("config_changed", "active_icon_pack", pkg)
	)
	
	# Initial visibility check
	shape_item.visible = (cur_pkg == "")
	
	# Item: Icon Shape
	var shape_options = OptionButton.new()
	shape_options.custom_minimum_size = Vector2(800, 120)
	shape_options.add_theme_font_size_override("font_size", 50)
	shape_options.add_theme_constant_override("arrow_margin", 40)
	shape_options.size_flags_horizontal = Control.SIZE_SHRINK_END
	
	# Apply Glass Style to Shape Options
	shape_options.add_theme_stylebox_override("normal", glass_style)
	shape_options.add_theme_stylebox_override("hover", glass_style)
	shape_options.add_theme_stylebox_override("pressed", glass_style)
	
	shape_item.add_child(shape_options)
	
	# --- Dropdown Styling Polish ---
	var style_popup = func(popup: PopupMenu):
		popup.add_theme_font_size_override("font_size", 50)
		popup.add_theme_constant_override("v_separation", 40) # Keep premium spacing
		
		# Keep the width restricted but let height be full
		popup.max_size = Vector2(900, 4000) 
		
	style_popup.call(pack_options.get_popup())
	var shapes = ["Circle", "Squircle", "Rounded Square", "Teardrop"]
	for s in shapes:
		shape_options.add_item(s)
		
	var cur_shape = Settings.current_config.get("icon_shape", "Circle")
	for i in range(shapes.size()):
		if shapes[i].to_lower() == cur_shape.to_lower():
			shape_options.selected = i
			break
			
	style_popup.call(shape_options.get_popup())
			
	# Sync initial shape to JNI if empty string (deep reset) was done or on first load
	if Engine.has_singleton("AppLoader"):
		Engine.get_singleton("AppLoader").set_active_icon_shape(cur_shape)
			
	shape_options.item_selected.connect(func(index):
		var shape = shapes[index]
		if Engine.has_singleton("AppLoader"):
			Engine.get_singleton("AppLoader").vibrate(40)
		
		Settings.clear_texture_cache() # V4.74: Clear cache to force refresh
		Settings.current_config.icon_shape = shape
		Settings.save_config()
		
		if Engine.has_singleton("AppLoader"):
			Engine.get_singleton("AppLoader").set_active_icon_shape(shape)
			
		emit_signal("config_changed", "icon_shape", shape)
	)

	# Item: Blur Level (V14.48: Re-enabled by user request)
	var blur_item = create_settings_item(visuals_box, "Blur Intensity", "Control the frosted glass effect depth")
	
	var blur_hbox = HBoxContainer.new()
	blur_hbox.add_theme_constant_override("separation", 20)
	
	var blur_slider = HSlider.new()
	blur_slider.min_value = 0.0
	blur_slider.max_value = 150.0 # Increased range for deeper blur
	blur_slider.step = 5.0
	blur_slider.value = Settings.current_config.get("blur_amount", 100.0)
	blur_slider.custom_minimum_size = Vector2(600, 180)
	blur_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Premium Deep Grabber for Touch
	var blur_grabber_tex = GradientTexture2D.new()
	blur_grabber_tex.fill = GradientTexture2D.FILL_RADIAL
	blur_grabber_tex.fill_from = Vector2(0.5, 0.5)
	blur_grabber_tex.fill_to = Vector2(0.8, 0.8)
	blur_grabber_tex.width = 110
	blur_grabber_tex.height = 110
	
	var blur_g = Gradient.new()
	blur_g.offsets = [0.0, 0.85, 0.86]
	blur_g.colors = [Color.WHITE, Color.WHITE, Color(1,1,1,0)]
	blur_grabber_tex.gradient = blur_g
	
	blur_slider.add_theme_icon_override("grabber", blur_grabber_tex)
	blur_slider.add_theme_icon_override("grabber_highlight", blur_grabber_tex)
	
	var blur_val_label = Label.new()
	blur_val_label.text = str(int(blur_slider.value))
	blur_val_label.add_theme_font_size_override("font_size", 50)
	blur_val_label.custom_minimum_size = Vector2(120, 0)
	blur_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	blur_slider.value_changed.connect(func(v):
		Settings.current_config.blur_amount = v
		blur_val_label.text = str(int(v))
		emit_signal("config_changed", "blur_amount", v)
		Settings.save_config()
	)
	
	blur_hbox.add_child(blur_slider)
	blur_hbox.add_child(blur_val_label)
	blur_item.add_child(blur_hbox)
	# Item: Opacity
	# var op_item = create_settings_item(visuals_box, "Column Opacity", "Subtle glass pillar transparency")
	# 
	# var opacity_hbox = HBoxContainer.new()
	# opacity_hbox.add_theme_constant_override("separation", 20)
	# 
	# var slider = HSlider.new()
	# slider.min_value = 0.0
	# slider.max_value = 1.0
	# slider.step = 0.05
	# slider.value = Settings.current_config.bg_opacity
	# slider.custom_minimum_size = Vector2(600, 180) # Taller for easier touch
	# slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 
	# # === NEW: MASSIVE GRABBER (100px for Big Fingers) ===
	# var grabber_tex = GradientTexture2D.new()
	# grabber_tex.fill = GradientTexture2D.FILL_RADIAL
	# grabber_tex.fill_from = Vector2(0.5, 0.5)
	# grabber_tex.fill_to = Vector2(0.8, 0.8)
	# grabber_tex.width = 100
	# grabber_tex.height = 100
	# 
	# var g = Gradient.new()
	# g.offsets = [0.0, 0.85, 0.86]
	# g.colors = [Color.WHITE, Color.WHITE, Color(1,1,1,0)]
	# grabber_tex.gradient = g
	# 
	# slider.add_theme_icon_override("grabber", grabber_tex)
	# slider.add_theme_icon_override("grabber_highlight", grabber_tex)
	# # No more stylebox overrides hiding the track
	# 
	# var percent_label = Label.new()
	# percent_label.text = str(int(Settings.current_config.bg_opacity * 100)) + "%"
	# percent_label.add_theme_font_size_override("font_size", 50)
	# percent_label.custom_minimum_size = Vector2(120, 0)
	# percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# 
	# slider.value_changed.connect(func(v):
	# 	Settings.current_config.bg_opacity = v
	# 	percent_label.text = str(int(v * 100)) + "%"
	# 	emit_signal("config_changed", "bg_opacity", v)
	# 	Settings.save_config() # Auto-Save
	# )
	# 
	# opacity_hbox.add_child(slider)
	# opacity_hbox.add_child(percent_label)
	# op_item.add_child(opacity_hbox)
	
	
	# Item: Minimal Mode
	# var minimal_item = create_settings_item(visuals_box, "Minimal Home Screen", "Show only 6 apps (3x2) at the bottom. No scrolling.")
	# create_pill_toggle.call(minimal_item, "Enable Minimal Mode", "minimal_mode")
	
	# Helpful Tip: Discoverability
	var tip = Label.new()
	tip.text = "Tip: Long-press widgets to configure them 💡"
	tip.add_theme_font_size_override("font_size", 34)
	tip.modulate = Color(1, 1, 1, 0.6)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visuals_box.add_child(tip)
	
	# Item: System Bars
	var bar_item = create_settings_item(visuals_box, "System Bars", "Control visibility of top and bottom bars")
	
	var bar_vbox = VBoxContainer.new()
	bar_vbox.add_theme_constant_override("separation", 30)
	bar_item.add_child(bar_vbox)
	
	create_pill_toggle.call(bar_vbox, "Always show Status bar", "show_status_bar")
	create_pill_toggle.call(bar_vbox, "Always show Navigation bar", "show_nav_bar")
	
	var widget_box = create_grouped_box(list, "Widget Drawer")
	var drawer_item = create_settings_item(widget_box, "Drawer Options", "Configure drawer visibility and behavior")
	
	var drawer_vbox = VBoxContainer.new()
	drawer_vbox.add_theme_constant_override("separation", 30)
	drawer_item.add_child(drawer_vbox)
	
	create_pill_toggle.call(drawer_vbox, "Enable Widget Drawer", "show_widget_drawer")
	
	# --- Sub-Options (Conditional on Drawer) ---
	var sub_box = VBoxContainer.new()
	sub_box.add_theme_constant_override("separation", 10)
	drawer_vbox.add_child(sub_box)
	
	var sub_margin = MarginContainer.new()
	sub_margin.add_theme_constant_override("margin_left", 80) # Indent
	sub_box.add_child(sub_margin)
	
	var sub_list = VBoxContainer.new()
	sub_list.add_theme_constant_override("separation", 20)
	sub_margin.add_child(sub_list)
	
	# New Dynamic Toggle
	# create_pill_toggle.call(sub_list, "Dynamic Positioning", "dynamic_widget_position")
	
	# Separator label for clarity
	var widgets_label = Label.new()
	widgets_label.text = "VISIBLE WIDGETS"
	widgets_label.add_theme_font_size_override("font_size", 30)
	widgets_label.modulate = Color(0.5, 0.5, 0.5)
	sub_list.add_child(widgets_label)
	
	create_pill_toggle.call(sub_list, "Show Clock", "show_clock_widget")
	create_pill_toggle.call(sub_list, "Show Battery", "show_battery_widget")
	create_pill_toggle.call(sub_list, "Show Weather", "show_weather_widget")
	create_pill_toggle.call(sub_list, "Show Date", "show_date_widget")
	
	var update_sub_vis = func():
		sub_box.visible = Settings.current_config.get("show_widget_drawer", true)
	
	update_sub_vis.call()
	config_changed.connect(func(k, v): if k == "show_widget_drawer": update_sub_vis.call())
	
	# Section: Performance
	# var perf_box = create_grouped_box(list, "Performance")
	# ... (Items commented out earlier)

	var tool_box = create_grouped_box(list, "System Tools")
	
	var perm_btn = create_btn(tool_box, "Enable Usage Access", "Required for Recent Apps functionality")
	perm_btn.pressed.connect(func():
		if Engine.has_singleton("AppLoader"):
			var loader = Engine.get_singleton("AppLoader")
			loader.vibrate(50)
			loader.request_usage_permission()
	)
	
	var def_btn = create_btn(tool_box, "Set as Default Launcher", "Set this app as your home")
	def_btn.pressed.connect(func(): if Engine.has_singleton("AppLoader"): Engine.get_singleton("AppLoader").select_default_launcher())

	var reset_btn = create_btn(tool_box, "Reset to Default", "Restore all settings to original state")
	reset_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4)) # Red Warning Color
	reset_btn.pressed.connect(func():
		if Engine.has_singleton("AppLoader"):
			Engine.get_singleton("AppLoader").vibrate(100)
		
		Settings.reset_to_defaults()
		
		# Instant feedback: Reload UI
		# Best way is to just close and let user reopen, or force a total reload.
		# For simplicity and robustness, verify changes by closing.
		# Or better: Reload the current scene?
		# Actually, since SettingsUI builds everything in _ready(), calling setup_ui() again might duplicate.
		# Let's just close the settings and show a toast/print?
		# User requested "Reset... clicking it will reset".
		# Let's close settings to apply visual changes cleanly.
		close_settings()
	)


func create_grouped_box(parent, title):
	var section_vbox = VBoxContainer.new()
	section_vbox.add_theme_constant_override("separation", 10)
	
	var l = Label.new()
	l.text = "   " + title.to_upper()
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	parent.add_child(l)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.04)
	style.corner_radius_top_left = 60
	style.corner_radius_top_right = 60
	style.corner_radius_top_right = 60
	style.corner_radius_bottom_left = 60
	style.corner_radius_bottom_right = 60
	style.content_margin_left = 50
	style.content_margin_right = 50
	style.content_margin_top = 40
	style.content_margin_bottom = 40
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE # Allow scroll through
	
	var box_vbox = VBoxContainer.new()
	box_vbox.add_theme_constant_override("separation", 60) # Increased from 40
	panel.add_child(box_vbox)
	
	parent.add_child(panel)
	return box_vbox

func create_settings_item(parent, title, sub):
	var item_vbox = VBoxContainer.new()
	item_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE # Allow scroll through
	item_vbox.add_theme_constant_override("separation", 10)
	
	var t = Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 55)
	item_vbox.add_child(t)
	
	var s = Label.new()
	s.text = sub
	s.add_theme_font_size_override("font_size", 35)
	s.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	item_vbox.add_child(s)
	
	parent.add_child(item_vbox)
	return item_vbox

func create_btn(parent, title, sub):
	var btn = Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(0, 140)
	
	var item = create_settings_item(btn, title, sub)
	item.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	parent.add_child(btn)
	return btn

func base64_to_texture(base64_string: String) -> ImageTexture:
	if base64_string == "": return null
	var image = Image.new()
	var raw_data = Marshalls.base64_to_raw(base64_string)
	if raw_data.is_empty(): return null
	if image.load_png_from_buffer(raw_data) == OK or image.load_jpg_from_buffer(raw_data) == OK or image.load_webp_from_buffer(raw_data) == OK:
		return ImageTexture.create_from_image(image)
	return null

func _on_back_pressed():
	# Just close this overlay
	close_settings()

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()
		get_tree().root.set_input_as_handled()

func _on_wallpaper_btn_pressed(btn: Button):
	# Direct attempt with fallback
	if Engine.has_singleton("AppLoader"):
		var loader = Engine.get_singleton("AppLoader")
		print("SettingsUI: Attempting Managed Wallpaper Pick...")
		
		# V4.66: Direct call. If Godot 4.x has a bug with has_method for plugins, 
		# the try-catch (or direct call) is more robust.
		loader.pick_launcher_wallpaper()
		
		# Feedback and Close
		if loader.has_method("make_toast"):
			loader.make_toast("Opening Wallpaper Settings...")
		close_settings() 
	else:
		# Ultimate Fallback: System Settings
		OS.shell_open("package:com.android.settings")
