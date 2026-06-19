extends Control

# Full-Screen Search Overlay
# - Dark background covering entire screen
# - 4-column grid for search results
# - Text input at bottom above keyboard
# - Apps sorted A-Z by name

signal app_selected(pkg: String)
signal request_context_menu(icon_node, pkg, label)

const IconScript = preload("res://scripts/Icon.gd")
const IconScene = preload("res://Icon.tscn")

var screen_size: Vector2
var background: ColorRect
var scroll_container: ScrollContainer
var grid_container: GridContainer
var input_container: Panel
var input_field: LineEdit
var close_btn: Button
var no_results_label: Label
var bar_height = 140
var keyboard_timer: Timer

# Store all apps for filtering
var all_apps: Array = []  # Array of {pkg, label}
var keyboard_was_visible = false  # Track keyboard state to detect back button dismissal

func _ready():
	print("SearchWidget: _ready() called")
	visible = false
	z_index = 200
	
	screen_size = get_viewport().get_visible_rect().size
	size = screen_size
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP  # Block input to main screen
	
	# Semi-transparent background - shows wallpaper through
	background = ColorRect.new()
	background.color = Color(0.0, 0.0, 0.0, 0.7)  # 70% opacity to show wallpaper
	background.size = screen_size
	background.position = Vector2.ZERO
	add_child(background)
	
	# Scroll container for results (fills screen above input bar)
	scroll_container = ScrollContainer.new()
	scroll_container.position = Vector2(0, 50)  # Small top margin
	scroll_container.size = Vector2(screen_size.x, screen_size.y - bar_height - 100)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll_container)
	
	# Container to push grid to bottom
	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(screen_size.x, 0)
	scroll_container.add_child(vbox)
	
	# Spacer to push grid down
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	# Grid container for app icons (4 columns)
	# Grid fills left-to-right, but we reverse the array so rightmost = first alphabetically
	grid_container = GridContainer.new()
	grid_container.columns = 4
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.add_theme_constant_override("h_separation", 10)
	grid_container.add_theme_constant_override("v_separation", 15)
	vbox.add_child(grid_container)
	
	# "No results" / prompt label
	no_results_label = Label.new()
	no_results_label.text = "Type to search apps..."
	no_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_results_label.add_theme_font_size_override("font_size", 42)
	no_results_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	no_results_label.position = Vector2(0, screen_size.y / 3.0)
	no_results_label.size = Vector2(screen_size.x, 60)
	add_child(no_results_label)
	
	# Input container at bottom
	input_container = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style.border_width_top = 4
	style.border_color = Color(0.7, 0.6, 0.0, 1.0)
	input_container.add_theme_stylebox_override("panel", style)
	input_container.mouse_filter = Control.MOUSE_FILTER_STOP
	input_container.size = Vector2(screen_size.x, bar_height)
	input_container.position = Vector2(0, screen_size.y - bar_height - 100)
	add_child(input_container)
	
	# Input field
	input_field = LineEdit.new()
	input_field.placeholder_text = "Search apps..."
	input_field.add_theme_font_size_override("font_size", 48)
	input_field.add_theme_color_override("font_color", Color.WHITE)
	input_field.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.5))
	
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
	input_style.set_corner_radius_all(12)
	input_style.set_content_margin_all(12)
	input_field.add_theme_stylebox_override("normal", input_style)
	input_field.add_theme_stylebox_override("focus", input_style)
	
	input_field.size = Vector2(screen_size.x - 120, 90)
	input_field.position = Vector2(20, 25)
	input_field.text_changed.connect(_on_text_changed)
	input_container.add_child(input_field)
	
	# Close button
	close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 48)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	
	var empty_style = StyleBoxEmpty.new()
	close_btn.add_theme_stylebox_override("normal", empty_style)
	close_btn.add_theme_stylebox_override("hover", empty_style)
	close_btn.add_theme_stylebox_override("pressed", empty_style)
	close_btn.add_theme_stylebox_override("focus", empty_style)
	
	close_btn.size = Vector2(80, 90)
	close_btn.position = Vector2(screen_size.x - 90, 25)
	close_btn.pressed.connect(close_search)
	input_container.add_child(close_btn)
	
	# Keyboard timer - only runs when search is open
	keyboard_timer = Timer.new()
	keyboard_timer.wait_time = 0.1
	keyboard_timer.one_shot = false  # Keeps repeating while running
	keyboard_timer.autostart = false  # Don't start automatically
	keyboard_timer.timeout.connect(_update_position_for_keyboard)
	add_child(keyboard_timer)
	
	# Load all apps on startup
	_load_all_apps()
	
	print("SearchWidget: _ready() complete")

func _load_all_apps():
	print("SearchWidget: _load_all_apps() called")
	
	if not Engine.has_singleton("AppLoader"):
		print("SearchWidget: ERROR - No AppLoader singleton!")
		return
	
	var app_loader = Engine.get_singleton("AppLoader")
	print("SearchWidget: Got AppLoader singleton")
	
	# Try calling get_installed_apps directly (has_method might not work for plugins)
	var json_str = ""
	json_str = app_loader.get_installed_apps()
	
	print("SearchWidget: Got JSON string, length=", json_str.length())
	
	if json_str.is_empty():
		print("SearchWidget: ERROR - Empty JSON string!")
		return
	
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		print("SearchWidget: ERROR - Failed to parse JSON: ", json.get_error_message())
		return
	
	var json_data = json.data
	if json_data == null:
		print("SearchWidget: ERROR - json.data is null!")
		return
	
	# JSON is an object with "apps" key containing the array
	var apps_array = json_data.get("apps", [])
	if apps_array.is_empty():
		print("SearchWidget: ERROR - No apps array in JSON!")
		return
	
	print("SearchWidget: Found ", apps_array.size(), " apps in JSON")
	
	all_apps.clear()
	
	for app_info in apps_array:
		var pkg = app_info.get("pkg", "")
		var label = app_info.get("name", pkg)  # Note: field is 'name' not 'label'
		if pkg != "":
			all_apps.append({
				"pkg": pkg,
				"label": label
			})
	
	# Sort by label A-Z
	all_apps.sort_custom(func(a, b): return a.label.to_lower() < b.label.to_lower())
	print("SearchWidget: Loaded ", all_apps.size(), " apps into all_apps array")

func open_search():
	print("SearchWidget: Opening search")
	visible = true
	input_field.text = ""
	input_field.grab_focus()
	keyboard_timer.start()
	
	# Clear grid and show prompt
	_clear_grid()
	no_results_label.text = "Type to search apps..."
	no_results_label.visible = true
	
	# Refresh apps list
	_load_all_apps()
	
	call_deferred("_update_position_for_keyboard")

func close_search():
	print("SearchWidget: Closing search")
	keyboard_timer.stop()  # Stop polling when search is closed
	keyboard_was_visible = false  # Reset state
	visible = false
	input_field.text = ""
	input_field.release_focus()
	_clear_grid()

func _clear_grid():
	for child in grid_container.get_children():
		child.queue_free()

func _on_text_changed(new_text: String):
	print("SearchWidget: Text changed to: ", new_text)
	
	_clear_grid()
	
	if new_text.is_empty():
		no_results_label.text = "Type to search apps..."
		no_results_label.visible = true
		return
	
	var query = new_text.to_lower()
	var matches: Array = []
	
	for app in all_apps:
		# Match only app name (not package name) for more intuitive results
		if query in app.label.to_lower():
			matches.append(app)
	
	if matches.is_empty():
		no_results_label.text = "No apps found for \"" + new_text + "\""
		no_results_label.visible = true
		return
	
	no_results_label.visible = false
	
	# Reverse matches so they appear from bottom right going up
	matches.reverse()
	
	# Create grid items for matches
	var icon_size = (screen_size.x - 60) / 4.0  # 4 columns with spacing
	
	# Add spacers to ensure bottom row is fully populated
	# If we have 5 items, the first row will have 1 item and 3 empty slots
	# We add 3 invisible spacers first so the bottom row is full
	var columns = 4
	var items_in_last_row = matches.size() % columns
	var spacers_needed = 0
	if items_in_last_row > 0:
		spacers_needed = columns - items_in_last_row
	
	for i in range(spacers_needed):
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(icon_size, icon_size + 80)
		grid_container.add_child(spacer)
	
	for app in matches:
		var item = _create_app_item(app, icon_size)
		grid_container.add_child(item)
	
	# Force grid to resize
	grid_container.size = Vector2(screen_size.x - 20, 0)

func _create_app_item(app: Dictionary, icon_size: float) -> Control:
	# Use the shared Icon component logic for consistency (and Long Press support)
	var body = IconScene.instantiate()
	if body == null: return Control.new()
	
	body.set_script(IconScript)
	body.package_name = app.pkg
	body.app_label = app.label
	body.custom_size = icon_size
	
	body.request_launch.connect(func(pkg): _launch_app(pkg))
	body.long_pressed.connect(func(node, pkg, label): 
		# Keep keyboard OPEN as per user request
		# input_field.release_focus() 
		emit_signal("request_context_menu", node, pkg, label)
	)
	
	return body

func _launch_app(pkg: String):
	print("SearchWidget: Launching app: ", pkg)
	
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		# Call launch_app directly (has_method doesn't work for plugins)
		app_loader.launch_app(pkg)
	
	close_search()

func _update_position_for_keyboard():
	if not visible:
		return
	
	# V14.49: Re-fetch screen size dynamically
	var visible_rect = get_viewport().get_visible_rect()
	var current_screen_height = visible_rect.size.y
	
	var keyboard_height = 0
	if Engine.has_singleton("AppLoader"):
		keyboard_height = Engine.get_singleton("AppLoader").get_keyboard_height()
	
	var keyboard_visible_now = keyboard_height > 100
	
	# Detect keyboard dismissal (was open, now closed) = back button pressed
	if keyboard_was_visible and not keyboard_visible_now:
		print("SearchWidget: Keyboard dismissed, closing search")
		keyboard_was_visible = false
		close_search()
		return
	
	keyboard_was_visible = keyboard_visible_now
	
	# V14.50: COORDINATE SPACE SYNC
	# keyboard_height is reported in physical display pixels (e.g., 1401px on a ~3000px screen).
	# current_screen_height is in virtual viewport pixels (e.g., 2400px).
	# We must scale the keyboard height to match our viewport's coordinate space.
	var physical_height = DisplayServer.screen_get_size().y
	# Fallback if physical_height is somehow reported smaller than visible
	if physical_height < current_screen_height: physical_height = current_screen_height
	
	var ratio = current_screen_height / float(physical_height)
	var kb_height_scaled = keyboard_height * ratio
	
	# Position input bar just above keyboard (or at bottom if no keyboard)
	var y_pos: float
	if keyboard_visible_now:
		# Use scaled height for accurate placement
		y_pos = current_screen_height - kb_height_scaled - bar_height
	else:
		y_pos = current_screen_height - bar_height
	
	# Debug to help fix the "gap" issue
	if keyboard_visible_now:
		var ds_kb = DisplayServer.virtual_keyboard_get_height()
		var safe_area = DisplayServer.get_display_safe_area()
		print("SearchWidget: KB Scale Fix -> Ratio: ", ratio, " PhysicalH: ", physical_height, " VirtualH: ", current_screen_height, " KB_Raw: ", keyboard_height, " KB_Scaled: ", kb_height_scaled, " ResultY: ", y_pos, " SafeB: ", safe_area.end.y)
	
	y_pos = max(y_pos, current_screen_height * 0.4)  # Don't go above 40% of screen
	input_container.position.y = y_pos
	
	# Resize scroll container to fit above input bar
	scroll_container.size.y = y_pos - 60

func _input(event):
	if not visible:
		return
	
	# Handle back button / escape to close search
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			# Release focus first to dismiss keyboard, then close
			input_field.release_focus()
			close_search()
			get_viewport().set_input_as_handled()
			return
	
	if event.is_action_pressed("ui_cancel"):
		input_field.release_focus()
		close_search()
		get_viewport().set_input_as_handled()
		return

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if visible:
			input_field.release_focus()
			close_search()
