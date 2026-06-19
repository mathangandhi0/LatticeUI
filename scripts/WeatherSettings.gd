extends CanvasLayer

signal settings_closed

var line_edit: LineEdit
var results_box: VBoxContainer
var http_search: HTTPRequest
var unit_btn: Button
var background_overlay: ColorRect
var main_panel: PanelContainer

func _init():
	print("WeatherSettings: _init() SUCCESS")

func _ready():
	print("WeatherSettings: _ready() START")
	layer = 120 # Above everything
	
	var screen_size = get_viewport().get_visible_rect().size
	var base_scale = screen_size.x / 1080.0
	
	# 1. Semi-transparent overlay to catch clicks outside
	background_overlay = ColorRect.new()
	background_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_overlay.color = Color(0, 0, 0, 0.45) # Slightly darker for focus
	background_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	background_overlay.gui_input.connect(_on_overlay_input)
	add_child(background_overlay)
	
	# 2. The floating box
	main_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.98) # Solid premium dark (almost opaque)
	style.set_corner_radius_all(30)
	style.set_content_margin_all(30 * base_scale) 
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.1) # Subtle border for depth
	main_panel.add_theme_stylebox_override("panel", style)
	
	main_panel.custom_minimum_size = Vector2(700 * base_scale, 0)
	
	# Default to centered hidden until open_at_widget positions it
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(main_panel)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 35 * base_scale)
	main_panel.add_child(main_vbox)
	
	var title_font = int(48 * base_scale)
	var btn_font = int(44 * base_scale)
	var btn_height = int(115 * base_scale)
	
	# Search Bar
	line_edit = LineEdit.new()
	line_edit.placeholder_text = "City Search..."
	line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_edit.custom_minimum_size = Vector2(0, btn_height)
	line_edit.add_theme_font_size_override("font_size", btn_font) 
	line_edit.text_submitted.connect(_on_search_submitted)
	main_vbox.add_child(line_edit)
	
	# Results Scroll
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 500 * base_scale)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	# Make the vertical scrollbar wider for touch
	var v_scroll = scroll.get_v_scroll_bar()
	v_scroll.custom_minimum_size.x = 60 * base_scale
	
	main_vbox.add_child(scroll)
	
	results_box = VBoxContainer.new()
	results_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_box.add_theme_constant_override("separation", 15 * base_scale)
	scroll.add_child(results_box)
	
	# Unit Toggle
	unit_btn = Button.new()
	var current_unit = Settings.current_config.get("weather_unit", "celsius")
	unit_btn.text = "TEMP UNIT: " + current_unit.to_upper()
	unit_btn.custom_minimum_size = Vector2(0, btn_height)
	unit_btn.add_theme_font_size_override("font_size", btn_font)
	unit_btn.pressed.connect(_on_unit_toggle)
	main_vbox.add_child(unit_btn)
	
	# HTTP for Search
	http_search = HTTPRequest.new()
	http_search.timeout = 10.0
	http_search.request_completed.connect(_on_search_completed)
	add_child(http_search)
	
	# Premium Entry Animation
	main_panel.modulate.a = 0
	main_panel.scale = Vector2(0.85, 0.85)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(main_panel, "modulate:a", 1.0, 0.25)
	tween.tween_property(main_panel, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func open_at_widget(widget_node: Control):
	var screen_size = get_viewport().get_visible_rect().size
	var widget_rect = widget_node.get_global_rect()
	
	# Manual Anchors
	main_panel.anchor_left = 0
	main_panel.anchor_right = 0
	main_panel.anchor_top = 0
	main_panel.anchor_bottom = 0
	
	# Layout wait
	await get_tree().process_frame
	if not is_instance_valid(main_panel): return
	
	var menu_size = main_panel.size
	main_panel.pivot_offset = menu_size / 2.0
	
	# 1. Horizontal Alignment
	var pos_x = widget_rect.position.x + (widget_rect.size.x / 2.0) - (menu_size.x / 2.0)
	pos_x = clamp(pos_x, 40.0, screen_size.x - menu_size.x - 40.0)
	
	# 2. Vertical Alignment
	# Position below widget with 25px gap
	var pos_y = widget_rect.position.y + widget_rect.size.y + 25
	
	# Flip Logic
	var bottom_limit = screen_size.y - 180 # Safe area above search/nav
	if pos_y + menu_size.y > bottom_limit:
		pos_y = widget_rect.position.y - menu_size.y - 25
		if pos_y < 100: pos_y = 100 # Top safe area
		
	main_panel.position = Vector2(pos_x, pos_y)
	print("WeatherSettings: Positioned at ", main_panel.position)

func _on_overlay_input(event):
	if event is InputEventScreenTouch and event.pressed:
		_on_close()

func _on_search_submitted(text: String):
	if text.length() < 2: return
	for child in results_box.get_children(): child.queue_free()
	var url = "https://geocoding-api.open-meteo.com/v1/search?name=%s&count=5&language=en&format=json" % text.uri_encode()
	http_search.request(url)

func _on_search_completed(_result, response_code, _headers, body):
	for child in results_box.get_children(): child.queue_free()
	if response_code != 200: return
	
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK:
		var results = json.data.get("results", [])
		if results == null: return
		for res in results:
			var btn = Button.new()
			btn.text = res.get("name", "") + " (" + res.get("country", "") + ")"
			btn.custom_minimum_size = Vector2(0, 100)
			btn.add_theme_font_size_override("font_size", 34)
			btn.pressed.connect(_on_city_selected.bind(res))
			results_box.add_child(btn)

func _on_city_selected(city_data):
	Settings.current_config["weather_city_data"] = {
		"name": city_data.get("name"),
		"lat": city_data.get("latitude"),
		"lon": city_data.get("longitude")
	}
	Settings.save_config()
	_on_close()

func _on_unit_toggle():
	var current = Settings.current_config.get("weather_unit", "celsius")
	var new_unit = "fahrenheit" if current == "celsius" else "celsius"
	Settings.current_config["weather_unit"] = new_unit
	Settings.save_config()
	unit_btn.text = "TEMP UNIT: " + new_unit.to_upper()

func _on_close():
	settings_closed.emit()
	queue_free()
