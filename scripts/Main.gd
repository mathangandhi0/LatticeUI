extends Node2D

var _app_icon_script
var _zone_manager_script
var _circle_shader
var _clock_script
var _date_script
var _battery_script
var _weather_script
var _category_header_script

var zone_manager
var _drawer: Control

var IconScene
var IconScript
var last_fetched_wp_id: int = -99 # V4.76: Optimization for Focus Return

func fetch_blurred_wallpaper(force: bool = false):
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		
		# V4.76j: EXPLICIT BRIDGE INVOCATION
		print("Main: fetch_blurred_wallpaper (force=", force, ")")
		
		# SMUGGLED ID (Direct via Call)
		var id_str_raw = app_loader.call("get_wp_id_v2")
		var current_id = -1
		if id_str_raw != null:
			current_id = int(str(id_str_raw))
		
		# Skip check if forced (e.g. radius changed)
		if not force:
			if current_id != -1 and current_id == last_fetched_wp_id:
				print("Main: Wallpaper ID unchanged, skipping.")
				return
		
		var radius = Settings.current_config.get("blur_amount", 25.0)
		var b64_str = app_loader.get_blurred_wallpaper(float(radius))
		if b64_str and b64_str != "":
			var buffer = Marshalls.base64_to_raw(b64_str)
			var image = Image.new()
			var err = image.load_jpg_from_buffer(buffer)
			if err == OK:
				image.generate_mipmaps() 
				var texture = ImageTexture.create_from_image(image)
				
				# V4.63: Dynamic Background Selection
				var raw_b64 = ""
				if app_loader.has_method("get_unblurred_wallpaper"):
					raw_b64 = app_loader.get_unblurred_wallpaper()
					
				var shield = get_node_or_null("WallpaperLayer/SafetyShield")
				if wp_texture_rect: wp_texture_rect.texture = texture
				
				if raw_b64 != "" and managed_bg_rect:
					var raw_tex = base64_to_texture(raw_b64)
					if raw_tex: 
						managed_bg_rect.texture = raw_tex
						managed_bg_rect.visible = true
						if shield: shield.color = Color(0, 0, 0, 1.0)
						if wp_texture_rect: wp_texture_rect.visible = false
						
						# V4.78: Panels respect the blur slider, Background remains sharp
						Settings.blurred_wallpaper_texture = texture
						print("Main: Background=Sharp, Panels=Blurred (Radius: ", radius, ")")
				else:
					if shield: shield.color = Color(0, 0, 0, 0)
					if managed_bg_rect: managed_bg_rect.visible = false
					if wp_texture_rect: wp_texture_rect.visible = false
					
					# Fallback to blurred texture for panels if sharp is missing
					Settings.blurred_wallpaper_texture = texture
				
				Settings.blurred_wallpaper_updated.emit()
				last_fetched_wp_id = current_id
				print("Main: Wallpaper updated (Radius: ", radius, ")")
			else:
				print("Main: JPG Decode Error: ", err)
	else:
		print("Main: AppLoader singleton not found for blur fetch")

func _apply_fallback_blur():
	# Create a simple 4x4 semi-transparent gray texture as fallback
	# This ensures the UI looks clean even if the wallpaper capture fails.
	var img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 0.2)) 
	Settings.blurred_wallpaper_texture = ImageTexture.create_from_image(img)
	if wp_texture_rect:
		wp_texture_rect.texture = Settings.blurred_wallpaper_texture
	
	# SHIELD FALLBACK: If fetch fails, we MUST make the shield transparent 
	# so the user can see their system wallpaper, even if it "leaks" sometimes.
	var shield = get_node_or_null("WallpaperLayer/SafetyShield")
	if shield:
		shield.color = Color(0, 0, 0, 0) # Transparent
		
	Settings.blurred_wallpaper_updated.emit()
	print("Main: Applied subtle gray fallback. Shield set to TRANSPARENT.")

func _init():
	# Try to load early but with fallback
	IconScene = load("res://Icon.tscn")
	IconScript = load("res://scripts/Icon.gd")
	if not IconScene: print("CRITICAL: Icon.tscn FAILED TO LOAD in _init")
	if not IconScript: print("CRITICAL: Icon.gd FAILED TO LOAD in _init")

var swipe_start_pos = Vector2.ZERO
var returning_from_background = false
var focus_out_time = 0

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focus_out_time = Time.get_ticks_msec()
		print("Main: Focus OUT")

	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		print("Main: Focus IN")
		apply_system_bars()
		
		var now = Time.get_ticks_msec()
		var duration = (now - focus_out_time) / 1000.0
		
		if duration > 0.5:
			# Real App Switch -> Enforce VSync and mark for bounce protection
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			returning_from_background = true
			get_tree().create_timer(1.0).timeout.connect(func(): returning_from_background = false)
			
			# SPECIFIC REFRESH: Check for Usage Access grant
			if Engine.has_singleton("AppLoader"):
				var app_loader = Engine.get_singleton("AppLoader")
				var currently_granted = app_loader.check_usage_permission()
				print("Main: Focus IN Permission Check - Currently Granted: ", currently_granted, " Previous: ", _usage_access_granted)
				
				if currently_granted and not _usage_access_granted:
					print("Main: Usage Access GRANTED - Soft refresh suppressed per user request")
					_usage_access_granted = true
				else:
					_usage_access_granted = currently_granted
					
				# V4.76j: Direct call bypass for focus return
				var id_res = app_loader.call("get_wp_id_v2")
				var curr = int(str(id_res)) if id_res != null else -1
					
				if curr != -1:
					if curr != last_fetched_wp_id:
						print("Main: Wallpaper changed in BG (", last_fetched_wp_id, " -> ", curr, ") - Fetching...")
						get_tree().create_timer(3.0).timeout.connect(fetch_blurred_wallpaper)
					else:
						print("Main: Focus Return - Wallpaper unchanged (ID: ", curr, "), skipping fetch.")
				else:
					get_tree().create_timer(3.0).timeout.connect(fetch_blurred_wallpaper)
		else:
			# Home Blip / Glitch -> Skip VSync change (Prevents Flicker)
			returning_from_background = false
		
		if returning_from_background:
			print("Main: Returning from background (App Switch) - Skipping Refresh")
			# MINIMAL REBUILD: Do not nuke icons just because we returned from another app.
			# This ensures the transition is smooth. Icon refreshes are handled by 
			# _on_package_changed or explicit reorders only.
			
			fade_in_launcher()
		
		if has_node("SettingsCanvas"):
			var canvas = get_node("SettingsCanvas")
			var overlay = canvas.get_node_or_null("SettingsOverlay")
			if overlay and overlay.has_method("close_settings"):
				overlay.close_settings()
			else:
				canvas.queue_free()

	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# V14.24: Block Back button entirely while the system is "Busy"
		if _is_refreshing:
			print("Main: Back Button BLOCKED (System is Busy)")
			return
			
		if current_ctx_menu:
			current_ctx_menu.queue_free()
			current_ctx_menu = null
		# User requested NO reset on Back button
		# elif zone_manager:
		# 	zone_manager.scroll_to_end()

func _process(_delta):
	# V4.76k: SHADERLESS ALIGNMENT (Real-time)
	# Align background blur layer with screen-space to appear fixed
	if current_ctx_menu and is_instance_valid(current_ctx_menu):
		var blur = current_ctx_menu.find_child("BlurLayer", true, false)
		if blur and is_instance_valid(blur):
			blur.global_position = Vector2.ZERO - current_ctx_menu.get_node("MainContainer").position if current_ctx_menu.has_node("MainContainer") else Vector2.ZERO
			# Simplified global alignment
			blur.global_position = Vector2.ZERO
			blur.size = get_viewport_rect().size

var current_ctx_menu = null
var wp_canvas: CanvasLayer = null 
var wp_texture_rect: TextureRect = null
var managed_bg_rect: TextureRect = null # V4.63: The raw background

var debug_label: Label
var pinned_app_pkgs: Array = []

# Busy Indicator / Input Lock components
var busy_layer: CanvasLayer = null
var busy_spinner: Label = null
var _busy_tween: Tween = null
var current_config = {
	"max_fps": 0,
	"bg_opacity": 0.25,
	"active_icon_pack": "",
	"icon_shape": "circle",
	"show_status_bar": false,
	"show_nav_bar": false,
	"show_widget_drawer": true
}

var _cached_app_list: Array = []
var _is_refreshing: bool = false
var _needs_default_pins: bool = false
var _usage_access_granted: bool = false

func load_config():
	if FileAccess.file_exists("user://config.json"):
		var f = FileAccess.open("user://config.json", FileAccess.READ)
		var json = JSON.parse_string(f.get_as_text())
		if json:
			for key in json:
				current_config[key] = json[key]

func load_pinned_apps():
	if FileAccess.file_exists("user://pinned.json"):
		var file = FileAccess.open("user://pinned.json", FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			pinned_app_pkgs = json.data
	else:
		_needs_default_pins = true
		pinned_app_pkgs = ["virtual:settings"]

func save_pinned_apps():
	var file = FileAccess.open("user://pinned.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(pinned_app_pkgs))

func _ready():
	# HIGH VISIBILITY VERIFICATION FILE
	var v_file = FileAccess.open("user://version_verify.txt", FileAccess.WRITE)
	if v_file:
		v_file.store_string("VERSION 14.2 - RUNNING AT " + str(Time.get_datetime_dict_from_system()))
		v_file.close()
		
	if not IconScene:
		IconScene = load("res://Icon.tscn")
		print("Main: Lazy-loading IconScene result: ", "OK" if IconScene else "FAIL")
	if not IconScript:
		IconScript = load("res://scripts/Icon.gd")
		print("Main: Lazy-loading IconScript result: ", "OK" if IconScript else "FAIL")
	
	_zone_manager_script = load("res://scripts/ZoneManager.gd")
	_circle_shader = load("res://shaders/circle.gdshader")
	# Load Scripts (Keep widget scripts for dynamic loading if needed)
	_clock_script = load("res://scripts/ClockWidget.gd")
	_date_script = load("res://scripts/DateWidget.gd")
	_battery_script = load("res://scripts/BatteryWidget.gd")
	_weather_script = load("res://scripts/WeatherWidget.gd")
	_category_header_script = load("res://scripts/CategoryHeader.gd")
	
	OS.low_processor_usage_mode = false # START IN HIGH PERFORMANCE
	get_tree().set_quit_on_go_back(false) 
	get_window().transparent_bg = true
	get_window().borderless = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	
	load_config()
	Engine.max_fps = current_config.get("max_fps", 0)
	
	# Initial System Bar setup
	apply_system_bars()
	
			
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		app_loader.force_high_refresh_rate()
		_usage_access_granted = app_loader.check_usage_permission()
		
		# Fetch System Long Press Time
		if app_loader.has_method("get_long_press_time_ms"):
			var ms = Engine.get_singleton("AppLoader").get_long_press_time_ms()
			Settings.system_long_press_time = ms / 1000.0
			print("Main: System Long Press Time: ", Settings.system_long_press_time, "s")
			
	# Connect to Global Settings Reset
	Settings.config_changed.connect(func(key, val):
		if key == "all":
			print("Main: Global Reset Detected - Reloading Config")
			# 1. Update Local Config Mirror
			load_config() 
			# 2. Apply System Bars
			apply_system_bars()
			# 3. Update Opacity on all pages
			for zm in zone_managers:
				zm.update_all_opacities(current_config.bg_opacity)
			# 4. Reset Icon Pack / Shape via JNI
			if Engine.has_singleton("AppLoader"):
				Engine.get_singleton("AppLoader").set_active_icon_pack("") # Default
				Engine.get_singleton("AppLoader").set_active_icon_shape("Circle") # Default
			# 5. Rebuild Widget Drawer (Crucial for Defaults)
			setup_widget_drawer()
			
			# 6. Full Refresh
			refresh_launcher(true, true, "Config: Global Reset")
		elif key == "bg_opacity":
			current_config["bg_opacity"] = val
			for zm in zone_managers:
				zm.update_all_opacities(val)
		elif key == "blur_amount":
			print("Main: Blur amount changed (", val, ") - live update")
			fetch_blurred_wallpaper(true)
		elif key == "active_icon_pack" or key == "icon_shape":
			# V4.74: Trigger full icon rebuild
			print("Main: Icon settings changed (", key, ") - Icon settings changed")
			# refresh_launcher(true, true, "Icon Settings Change") # Suppressed until explicit refresh requested
			pass
	)



	load_pinned_apps()
	
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		if app_loader.has_signal("on_wallpaper_changed"):
			# V4.77: On wallpaper change, force re-fetch blur.
			# If importSystemWallpaper() failed (Android 13+), the next fetch
			# will use the managed file if it exists. On first change after install,
			# capture_wallpaper() prompts the user for screen capture consent.
			app_loader.on_wallpaper_changed.connect(func():
				print("Main: on_wallpaper_changed received — scheduling blur refresh")
				last_fetched_wp_id = -99  # Force re-fetch regardless of ID match
				get_tree().create_timer(1.5).timeout.connect(fetch_blurred_wallpaper)
			)
			print("Main: Connected to on_wallpaper_changed (V4.77 MediaProjection)")
		
		if not app_loader.is_connected("home_pressed", _on_home_pressed):
			app_loader.connect("home_pressed", _on_home_pressed)
			print("Main: Connected to home_pressed signal")

	if OS.get_name() == "Android":
		OS.request_permissions()
		# V4.55: Restore 1s delay to prevent startup race/hang
		get_tree().create_timer(1.0).timeout.connect(fetch_blurred_wallpaper)
	else:
		fetch_blurred_wallpaper()
	
	setup_pages()
	setup_background_layer()
	setup_widget_drawer()
	
	# Apply Icon Pack on Startup
	if Engine.has_singleton("AppLoader"):
		var pack = current_config.get("active_icon_pack", "")
		if pack != "":
			print("Main: Applying active icon pack: ", pack)
			Engine.get_singleton("AppLoader").set_active_icon_pack(pack)
			
		# Apply Icon Shape
		var shape = current_config.get("icon_shape", "Circle")
		print("Main: Applying icon shape: ", shape)
		Engine.get_singleton("AppLoader").set_active_icon_shape(shape)

	# Initial Launch - Force Reset to Recents
	call_deferred("refresh_launcher", true, false, "Initial Startup")
	
	setup_busy_indicator()

func apply_system_bars():
	if Engine.has_singleton("AppLoader"):
		var loader = Engine.get_singleton("AppLoader")
		var s = current_config.get("show_status_bar", false)
		var n = current_config.get("show_nav_bar", false)
		loader.set_system_bars_visibility(s, n)

func setup_widget_drawer():
	print("Main: setup_widget_drawer -> START")
	# 1. Cleanup old drawer(s) - Robust check
	# Iterate children to find any CanvasLayer that might be a drawer
	for child in get_children():
		if child is CanvasLayer and (child.name == "WidgetDrawerLayer" or child.layer == 100):
			child.queue_free()
	
	# Check if widget drawer is enabled
	if not current_config.get("show_widget_drawer", true):
		print("Main: Widget drawer disabled in settings")
		_drawer = null
		for zm in zone_managers:
			if is_instance_valid(zm):
				zm.active_drawer_ref = null
		return
	
	# 2. Setup New Drawer
	var drawer_script = load("res://scripts/WidgetDrawer.gd")
	if not drawer_script:
		print("Main: CRITICAL ERROR - WidgetDrawer.gd failed to load!")
		var err_label = Label.new()
		err_label.text = "DRAWER SCRIPT ERROR - See Logcat"
		err_label.position = Vector2(100, 100)
		err_label.modulate = Color(1, 0, 0, 1) # Red
		add_child(err_label)
		return
		
	var drawer = drawer_script.new()
	
	# Input Isolation V2: Use a high-priority CanvasLayer
	var canvas = CanvasLayer.new()
	canvas.name = "WidgetDrawerLayer"
	canvas.layer = 100 # Above icons and status bars
	add_child(canvas)
	
	canvas.add_child(drawer)
	_drawer = drawer
	# Assign drawer ref to ALL zone managers (Page 1 & 2)
	for zm in zone_managers:
		if is_instance_valid(zm):
			zm.active_drawer_ref = drawer
	

	# 3. Add Top Spacer (50px) to avoid status bar overlap
	drawer.add_spacer(50)
	
	if Settings.current_config.get("show_clock_widget", true):
		print("Main: Adding Clock Widget...")
		var clock = _clock_script.new()
		drawer.add_widget(clock)
		print("Main: Clock Added.")
	
	
	if Settings.current_config.get("show_weather_widget", true) and _weather_script:
		print("Main: Adding Weather Widget (Type: ", _weather_script.get_class(), ")...")
		if _weather_script.can_instantiate():
			var weather = _weather_script.new()
			if weather:
				drawer.add_widget(weather)
				weather.settings_requested.connect(show_weather_settings)
				print("Main: Weather Added to Drawer and Connected.")
			else:
				print("Main: Weather Instance is NULL.")
		else:
			print("Main: Weather Script CANNOT instantiate.")
	else:
		print("Main: Weather Widget OMITTED (Disabled or Script Null)")
	
	drawer.add_expander() # Pushes everything below it to the bottom
	
	if Settings.current_config.get("show_date_widget", true) and _date_script:
		print("Main: Adding Date Widget...")
		var date = _date_script.new()
		drawer.add_widget(date)
		print("Main: Date Added.")
	else:
		print("Main: Date Widget OMITTED (Disabled or Script Null)")
	
	if Settings.current_config.get("show_battery_widget", true) and _battery_script:
		print("Main: Adding Battery Widget (Post-Date Position)...")
		var battery = _battery_script.new()
		drawer.add_widget(battery)
		print("Main: Battery Added.")
	
	# Dynamic Bottom Spacer (Fixed 20px gap as requested)
	drawer.add_spacer(20)
	
	setup_settings_button() # Re-add settings/search buttons to new drawer at the very end
	
	print("Main: setup_widget_drawer -> END (SUCCESS)")

func _on_package_changed(pkg: String = ""):
	# V14.28: Selective Texture Clearing
	if pkg != "":
		Settings.clear_texture_cache(pkg)
		
	# V14.28: Faster refresh. BusyLayer ensures user is blocked during this time.
	await get_tree().create_timer(0.4).timeout
	print("Main: Package changed (", pkg, ") - invalidating cache and refreshing")
	refresh_launcher(true, true, "Package Changed: " + pkg)

func _on_home_pressed():
	print("Main: Home signal received - Switching to Home Page")
	if has_node("SettingsCanvas"):
		var canvas = get_node("SettingsCanvas")
		var settings = canvas.get_node_or_null("SettingsOverlay")
		if settings and settings.has_method("close_settings"):
			settings.close_settings()
		else:
			canvas.queue_free()
			fade_in_launcher()
	
	# Global Page Reset to Page 0
	change_page(0)
	
	# RECOVERY: Clear background return flag on Home press to ensure responsiveness
	returning_from_background = false
	
	# Reset ALL pages (Home & Drawer)
	for zm in zone_managers:
		if is_instance_valid(zm):
			# Reset search filter
			if zm.has_method("reset_filter"):
				zm.reset_filter()
			
			# Reset Vertical Scroll
			if zm.has_method("reset_vertical_offsets"):
				zm.reset_vertical_offsets(true) # Smooth = true
			
			# Reset Horizontal Scroll (To column 0)
			if zm.has_method("scroll_to_column"):
				zm.scroll_to_column(0)
	
	# Close search input if open
	var search_layer = get_node_or_null("SearchLayer")
	if search_layer:
		for child in search_layer.get_children():
			if child.has_method("close_search"):
				child.close_search()


func get_apps(invalidate_cache: bool = false):
	# Flag is now managed by the caller (refresh_launcher) to avoid interlocking
	if not _is_refreshing:
		print("Main: WARNING - get_apps called without _is_refreshing flag set!")
	
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		if not app_loader.is_connected("package_changed", _on_package_changed):
			app_loader.package_changed.connect(_on_package_changed)
			
		if not app_loader.is_connected("home_pressed", _on_home_pressed):
			app_loader.connect("home_pressed", _on_home_pressed)
			
		if app_loader.has_method("update_system_ui"):
			app_loader.update_system_ui()
			
		if invalidate_cache or _cached_app_list.is_empty():
			print("Main: Fetching apps from AppLoader...")
			var json_str = app_loader.get_installed_apps()
			print("Main: JNI get_installed_apps returned string length: ", json_str.length() if json_str else 0)
			if json_str != "":
				var json = JSON.new()
				if json.parse(json_str) == OK:
					var data = json.data
					_cached_app_list = data.get("apps", [])
					print("Main: Parsed ", _cached_app_list.size(), " apps from system")
					
					# 1. Inject Virtual Apps
					_cached_app_list.append({
						"pkg": "virtual:settings",
						"name": "Lattice Ui Settings"
					})
					if data.has("battery_level"):
						Settings.battery_level = data.get("battery_level")
						Settings.is_charging = data.get("is_charging", false)
		
		# Staggered Spawn (Awaited to maintain sync)
		await spawn_apps(_cached_app_list)
	else:
		print("Main: Missing AppLoader singleton!")
	
	_is_refreshing = false
	set_busy(false)
			
func spawn_apps(app_list: Array):
	# if app_list.is_empty(): return # Allow empty list to initialize recents/pinned
		
	app_list.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	var chunks = []
	var current_char = ""
	var current_chunk = []
	
	for app in app_list:
		var char_start = app.get("name", "Unknown").left(1).to_upper()
		if current_chunk.is_empty():
			current_chunk.append({"type": "header", "label": char_start, "special": false})
			current_char = char_start
		elif char_start != current_char:
			current_char = char_start
			current_chunk.append({"type": "header", "label": current_char, "special": false})
		
		current_chunk.append({"type": "app", "data": app})
		if current_chunk.size() >= 15:
			chunks.append(current_chunk)
			current_chunk = []
			
	if not current_chunk.is_empty(): chunks.append(current_chunk)
	
	var pinned_chunk = []
	pinned_chunk.append({"type": "header", "label": "Pinned", "special": true})
	for pkg in pinned_app_pkgs:
		for app in app_list:
			if app.get("pkg") == pkg:
				pinned_chunk.append({"type": "app", "data": app})
				break
	
	# Limit Pinned to 30 (10 per column for 3 columns)
	if pinned_chunk.size() > 31: # 30 apps + 1 header
		pinned_chunk.resize(31)
	
	chunks.append(pinned_chunk) 
	
	# Determine Pinned Column Index (chunks size is length, so it's index size-1)
	if zone_manager and zone_manager.has_method("set_pinned_column_index"):
		zone_manager.set_pinned_column_index(chunks.size() - 1)
		
	var recents_chunk = []
	recents_chunk.append({"type": "header", "label": "Recent", "special": true})
	
	# --- RECENTS LOGIC V2 ---
	var new_apps = []
	var used_apps_pkgs = []
	var final_recents = []
	
	# 1. Identify NEW Apps (Installed < 24 Hours)
	var now = Time.get_unix_time_from_system() * 1000.0 # ms
	var one_day_ms = 24 * 60 * 60 * 1000.0
	
	print("Main: Time Debug - Now: ", now)
	
	for app in app_list:
		# Filter: Don't show in Recents/New if already Pinned
		var pkg = app.get("pkg", "")
		if pkg in pinned_app_pkgs: continue
		
		var install_time = app.get("firstInstallTime", 0)
		if install_time > 0 and (now - install_time) < one_day_ms:
			new_apps.append(app)
			
	# Sort Newest First
	new_apps.sort_custom(func(a, b): return a.get("firstInstallTime", 0) > b.get("firstInstallTime", 0))
	
	# Limit New Apps to 5
	if new_apps.size() > 5: new_apps.resize(5)
	
	for app in new_apps:
		final_recents.append(app)
		
	# 2. Identify USED Apps (UsageStats)
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		var used_json = app_loader.fetch_usage_stats() 
		
		if used_json == "PERMISSION_DENIED":
			# Add a dummy item that triggers permission request
			recents_chunk.append({"type": "usage_permission_btn"})
		else:
			var json = JSON.new()
			if json.parse(used_json) == OK:
				var used_list = json.data
				
				# --- DEFAULT PINS LOGIC ---
				if _needs_default_pins:
					# 1. PHASE 1: Usage Stats (Top Priority)
					if used_list.size() > 0:
						for u in used_list:
							if pinned_app_pkgs.size() >= 30: break
							var pkg = u.get("pkg", "")
							if pkg != "" and not pkg in pinned_app_pkgs:
								pinned_app_pkgs.append(pkg)
								# Add to current chunk validly
								for app in app_list:
									if app.get("pkg") == pkg:
										pinned_chunk.append({"type": "app", "data": app})
										break
					
					# 2. PHASE 2: Popularity Heuristic (Curated List)
					if pinned_app_pkgs.size() < 30:
						var popular_pkgs = [
							"com.whatsapp", "com.instagram.android", "com.facebook.katana", "com.zhiliaoapp.musically", # Social
							"com.google.android.youtube", "com.netflix.mediaclient", "com.spotify.music", # Media
							"com.google.android.gm", "com.google.android.apps.maps", "com.android.chrome", "com.google.android.apps.photos", # Google Core
							"org.telegram.messenger", "com.discord", "com.twitter.android", "com.snapchat.android", # Comm
							"com.amazon.mShop.android.shopping", "com.ubercab", "com.linkedin.android", # Utility
							"com.microsoft.office.outlook", "com.microsoft.teams", "com.google.android.calendar" # Prod
						]
						
						for pop_pkg in popular_pkgs:
							if pinned_app_pkgs.size() >= 30: break
							# Check if installed
							for app in app_list:
								if app.get("pkg") == pop_pkg and not pop_pkg in pinned_app_pkgs:
									pinned_app_pkgs.append(pop_pkg)
									pinned_chunk.append({"type": "app", "data": app})
									break
					
					# 3. PHASE 3: Alphabetical Fill (Installed Apps)
					if pinned_app_pkgs.size() < 30:
						for app in app_list:
							if pinned_app_pkgs.size() >= 30: break
							var pkg = app.get("pkg", "")
							# Skip if already pinned or is special/hidden
							if not pkg in pinned_app_pkgs and not pkg.begins_with("virtual:"):
								pinned_app_pkgs.append(pkg)
								pinned_chunk.append({"type": "app", "data": app})
					
					save_pinned_apps()
					_needs_default_pins = false
					print("Main: Default pins initialized. Total: ", pinned_app_pkgs.size())
				
				var count = 0
				for u in used_list:
					if count >= 7: break
					var pkg = u.get("pkg", "")
					if pkg == "": continue
					
					# Check if already added via "New Apps"
					var already_added = false
					for existing in final_recents:
						if existing.get("pkg", "") == pkg: 
							already_added = true
							break
					if already_added: continue
					
					# Find full app data
					for app in app_list:
						if app.get("pkg", "") == pkg:
							final_recents.append(app)
							count += 1
							break
			else:
				print("Main: Failed to parse used_json")
	
	# 4. Fallback if Empty 
	if final_recents.is_empty():
		if Engine.has_singleton("AppLoader") and Engine.get_singleton("AppLoader").check_usage_permission():
			# Permission Granted but no data yet
			recents_chunk.append({"type": "header", "label": "No Recent Apps", "special": true})
		else:
			# Permission Missing
			recents_chunk.append({"type": "header", "label": "Enable in\nSettings", "special": true})
	else:
		# 3. Add to Chunk (Limit to 10 for Column 3)
		var recent_count = 0
		for app in final_recents:
			if recent_count >= 10: break
			recents_chunk.append({"type": "app", "data": app})
			recent_count += 1
		
	chunks.append(recents_chunk)
		
	# Column Reordering for Left Handed Mode
	var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var columns = []
	
	# Helper to check if a specific alpha character has active content in 'chunks'
	var has_alpha_content = func(char):
		for chunk in chunks:
			if not chunk.is_empty() and chunk[0].type == "header" and chunk[0].label == char and not chunk[0].get("special", false):
				return true
		return false

	# REORDERED: [A-Z..., Pinned, Recents] (Recents hidden to right)
	for char in alphabet:
		if has_alpha_content.call(char):
			columns.append({"type": "alpha", "label": char})
			
	columns.append({"type": "pinned", "label": "Pinned", "icon": "res://assets/pinned.png"})
	columns.append({"type": "recents", "label": "Recent", "icon": "res://assets/recents.png"})
		
	# 5. Spawning Loop with Staggering
	var spawn_counter = 0
	
	# Loop through BOTH pages
	for z_idx in range(zone_managers.size()):
		var target_zm = zone_managers[z_idx]
		target_zm.reinit_columns(4) # Both pages are 4-column wide in this design
		
		if z_idx == 0:
			# --- PAGE 1: HOME (Pinned + Recents) ---
			if Settings.current_config.get("minimal_mode", false):
				# MINIMAL MODE: 3x2 Grid at Bottom
				print("Main: Minimal Mode Active - Populating 3x2 grid")
				
				# First-run initialization check
				if not Settings.current_config.get("minimal_home_initialized", false):
					init_minimal_home(_cached_app_list)
				
				var home_apps = Settings.current_config.get("minimal_home_apps", [])
				target_zm.reinit_columns(3) # Use 3 columns
				
				# STABLE BOTTOM-RIGHT PACKING
				# Grid: 0 1 2 (Top)
				#       3 4 5 (Bottom)
				var slots = [null, null, null, null, null, null]
				var count = home_apps.size()
				
				# Fill from the last slot (5) backwards to keep them at the bottom
				for i in range(count):
					var slot_idx = 5 - i
					if slot_idx >= 0:
						slots[slot_idx] = home_apps[count - 1 - i]
				
				for col in range(3):
					# Row 0 (Top)
					var pkg0 = slots[col]
					if pkg0:
						var app_data = _find_app_in_list(pkg0, _cached_app_list)
						if app_data: create_icon(app_data, col, target_zm)
						else: create_spacer(col, target_zm)
					else:
						create_spacer(col, target_zm)
						
					# Row 1 (Bottom)
					var pkg1 = slots[col + 3]
					if pkg1:
						var app_data = _find_app_in_list(pkg1, _cached_app_list)
						if app_data: create_icon(app_data, col, target_zm)
						else: create_spacer(col, target_zm)
					else:
						create_spacer(col, target_zm)
					
					spawn_counter += 2
					if spawn_counter >= 5:
						await get_tree().process_frame
						spawn_counter = 0
				
				# No Recents in Minimal Mode per request for "cleanliness"
			else:
				# Layout: [Pinned (Col 0), Pinned (Col 1), Pinned (Col 2), Recents (Col 3)]
				print("Main: Populating Page 1 (Home) - Pinned 0-2, Recents 3")
				
				# 1. Extract Pinned Apps
				var pinned_items = []
				for item in pinned_chunk:
					if item.type == "app": pinned_items.append(item)
				
				# 2. Distribute Pinned Apps across 3 columns (Reverse Order: 2, 1, 0) - Dynamic Limit
				var total_pins = pinned_items.size()
				if total_pins > 0:
					# Dynamic Distribution: Split evenly across 3 columns
					var pins_per_col = ceil(total_pins / 3.0)
					
					for i in range(3):
						var col_index = 2 - i  # Column 2, then 1, then 0
						var start = i * pins_per_col
						var end = min(start + pins_per_col, total_pins)
						
						# Safety: Ensure start is within bounds
						if start >= total_pins: break
						
						for k in range(int(start), int(end)):
							create_icon(pinned_items[k].data, col_index, target_zm)
							spawn_counter += 1
							if spawn_counter >= 5:
								await get_tree().process_frame
								spawn_counter = 0
				else:
					print("Main: Page 1 - WARNING: No Pinned Apps found.")
						
				# 3. Recents in Column 3
				# Add Header first
				var r_header = _category_header_script.new("RECENT", load_external_texture("res://assets/header_recents.png"))
				if r_header:
					r_header.set_meta("launcher_item", true)
					target_zm.register_icon(r_header, 3)
					
				for item in recents_chunk:
					if item.type == "app":
						create_icon(item.data, 3, target_zm)
						spawn_counter += 1
						if spawn_counter >= 5:
							await get_tree().process_frame
							spawn_counter = 0
					
		else:
			# --- PAGE 2: DRAWER (Recents + A-Z) ---
			
			print("Main: Populating Page 2 (Drawer) - Recents 0, A-Z 1-3")
			
			# 1. COLUMN 0: RECENTS
			var r_header = _category_header_script.new("RECENT", load_external_texture("res://assets/header_recents.png"))
			if r_header:
				r_header.set_meta("launcher_item", true)
				target_zm.register_icon(r_header, 0)
			
			for item in recents_chunk:
				if item.type == "app":
					create_icon(item.data, 0, target_zm)
					spawn_counter += 1
					if spawn_counter >= 5:
						await get_tree().process_frame
						spawn_counter = 0

			# 2. COLUMNS 1-3: A-Z (Flattened & Distributed)
			# 2. COLUMNS 1-3: A-Z (Flattened & Distributed)
			var all_az_items = []
			
			# FIX: Iterate chunks directly. 'columns' mapping is legacy and incorrect for this layout.
			var last_header = ""
			
			for chunk in chunks:
				if chunk.is_empty(): continue
				
				# Check first item to identify chunk type
				var first = chunk[0]
				var is_special = false
				if first.type == "header":
					if first.get("special", false) == true:
						is_special = true
				
				# Append only standard A-Z app chunks
				if not is_special:
					for item in chunk:
						if item.type == "header":
							if item.label == last_header:
								continue # Skip Duplicate Header
							last_header = item.label
						all_az_items.append(item)
			
			var total_az = all_az_items.size()
			if total_az > 0:
				var current_index = 0
				var remaining_items = float(total_az)
				
				for col_offset in range(3):
					var target_col_idx = 1 + col_offset
					
					# Dynamic target count based on remaining items & columns
					var cols_left = 3 - col_offset
					var target_count = ceil(remaining_items / float(cols_left))
					
					var start = current_index
					var end = min(start + int(target_count), total_az)
					
					# ORPHAN HEADER CHECK:
					# If the LAST item in this column (end-1) is a header,
					# and there are more items effectively, push it to next column.
					if end < total_az and end > start:
						var last_item = all_az_items[end - 1]
						if last_item.type == "header":
							end -= 1
					
					for k in range(start, end):
						var item = all_az_items[k]
						if item.type == "header":
							var header = _category_header_script.new(item.label, null)
							if header:
								header.name = "Header_" + item.label
								header.set_meta("launcher_item", true)
								target_zm.register_icon(header, target_col_idx)
						elif item.type == "app":
							create_icon(item.data, target_col_idx, target_zm)
							
					current_index = end
					remaining_items = total_az - current_index
	
	await get_tree().process_frame
	
	# Restore Scroll Position if available
	if not _temp_scroll_state.is_empty():
		if zone_manager and zone_manager.has_method("restore_state"):
			print("Main: Restoring scroll state")
			zone_manager.restore_state(_temp_scroll_state)
		_temp_scroll_state = {}
	elif zone_manager and zone_manager.has_method("scroll_to_column"):
		# Default to Start (Pinned Apps) for Page 1 logic
		zone_manager.scroll_to_column(0) 
		pass

func load_external_texture(path: String) -> Texture2D:
	# Method 1: Standard Godot load (works with imported .ctex files)
	var tex = load(path)
	if tex:
		print("Main: Loaded texture via standard load: ", path)
		return tex
		
	# Fallback: Try loading as Image > ImageTexture (if import failed)
	if FileAccess.file_exists(path):
		var img = Image.new()
		var err = img.load(path)
		if err == OK:
			print("Main: Loaded texture via Image.load() fallback: ", path)
			return ImageTexture.create_from_image(img)
	
	print("Main: Standard load() returned null for: ", path)
	
	# Method 2: Try without res:// prefix
	var alt_path = path.replace("res://", "")
	tex = load(alt_path)
	if tex:
		print("Main: Loaded texture via alt path: ", alt_path)
		return tex
	
	# Method 3: JNI AssetManager for raw PNG files (non-imported)
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		var jni_path = path.replace("res://", "")
		
		print("Main: Trying JNI load for: ", jni_path)
		
		# Try Base64 transfer - call directly without has_method check
		var b64 = app_loader.call("loadAssetBase64", jni_path)
		print("Main: JNI loadAssetBase64 returned: ", typeof(b64), " len=", str(b64).length() if b64 else 0)
		
		if b64 != null and b64 != "":
			var bytes = Marshalls.base64_to_raw(b64)
			if bytes.size() > 0:
				print("Main: JNI returned ", bytes.size(), " bytes for: ", jni_path)
				var jni_img = Image.new()
				var err = jni_img.load_png_from_buffer(bytes)
				if err == OK:
					print("Main: JNI PNG parse SUCCESS for: ", jni_path)
					return ImageTexture.create_from_image(jni_img)
				else:
					print("Main: JNI PNG parse FAILED with error ", err, " for: ", jni_path)
					# Try JPG/WebP as fallback
					if jni_img.load_jpg_from_buffer(bytes) == OK:
						return ImageTexture.create_from_image(jni_img)
					if jni_img.load_webp_from_buffer(bytes) == OK:
						return ImageTexture.create_from_image(jni_img)
	
	print("Main: FAILED to load texture: ", path)
	return null



func create_icon(app_data, col_index, target_zone = null):
	if not IconScene:
		print("Main: SKIPPING Icon creation - IconScene is NULL")
		return
		
	var body = IconScene.instantiate()
	
	if body == null: 
		print("Main: FAILED to instantiate IconScene for ", app_data.get("pkg"))
		return

	# Always force the preloaded script to avoid broken scene refs
	body.set_script(IconScript)

	# Use set() to bypass strict typing crashes for debugging
	body.set("package_name", app_data.get("pkg", ""))
	body.set("app_label", app_data.get("name", "App"))
	
	# Pass Shape Override Explicitly
	var shape = current_config.get("icon_shape", "Circle")
	body.set("custom_shape_override", shape)
	
	if body.has_signal("long_pressed"):
		body.long_pressed.connect(show_context_menu)
	
	if target_zone:
		# Set is_home flag for reordering logic
		if target_zone == zone_managers[0]:
			body.is_home = true
		
		# target_zone.add_child(body) # Removed: register_icon handles parenting
		body.set_meta("launcher_item", true)
		target_zone.register_icon(body, col_index)
	else:
		# Fallback (Should not happen in new logic)
		add_child(body)
		if body.is_inside_tree() and zone_manager:
			body.set_meta("launcher_item", true)
			zone_manager.register_icon(body, col_index)
			
	if body.has_signal("drag_started"):
		body.drag_started.connect(func(_node): 
			_on_icon_drag_started(_node)
		)
		body.drag_moved.connect(func(_node, pos):
			_on_icon_drag_moved(_node, pos)
		)
		body.drag_ended.connect(func(_node, pos):
			_on_icon_drag_ended(_node, pos)
		)

func _on_icon_drag_started(_node):
	close_context_menu()
	if zone_managers.size() > 0: zone_managers[0].is_drag_active = true

func _on_icon_drag_moved(_icon_node, pos: Vector2):
	var zm = zone_managers[0]
	if zm:
		zm.show_drop_preview(pos)

func _on_icon_drag_ended(icon_node, global_pos):
	var target: Dictionary = {}
	if zone_managers.size() > 0: 
		var zm = zone_managers[0]
		if zm:
			zm.clear_drop_preview()
			target = zm.get_drop_target(global_pos)
			print("Main: Drop Pos: ", global_pos, " -> Target: ", target)
			
		# PERSISTENT BLOCK: Clear paging state to prevent "Throw to App Drawer"
		_page_dragging = false
		_page_drag_start = Vector2.ZERO
		# Delay reset to ensure release event is consumed by GUI first
		get_tree().create_timer(0.1).timeout.connect(func(): if zone_managers.size() > 0: zone_managers[0].is_drag_active = false)
	
	if target.is_empty(): 
		refresh_launcher(false, false, "Icon Drag Ended (No Target)")
		return
		
	var target_col = target.column
	var target_row = target.index
	var pkg = icon_node.get("package_name")

	# === MINIMAL MODE REORDER ===
	if Settings.current_config.get("minimal_mode", false):
		_handle_minimal_reorder(pkg, target_col, target_row)
		return
		
	# === STANDARD REORDER (3 Pinned Columns) ===
	if target_col > 2:
		print("Main: Drop ignored - outside pinned columns")
		refresh_launcher(false, false, "Icon Drag Ended (Outside Pinned Columns)")
		return
		
	var old_idx = pinned_app_pkgs.find(pkg)
	if old_idx == -1:
		refresh_launcher(false, false, "Icon Drag Ended (Not Pinned)")
		return
		
	# 2. Logic to map Column/Row to Flat Array Index (Reverse 2->1->0)
	# V14.53: We MUST use the same 'valid pins' logic as spawn_apps
	var valid_pins = []
	for p_pkg in pinned_app_pkgs:
		if _find_app_in_list(p_pkg, _cached_app_list):
			valid_pins.append(p_pkg)
			
	var total_pins = valid_pins.size()
	var pins_per_col = ceil(total_pins / 3.0)
	
	var final_target_idx = 0
	# Calculate index within the 'valid' list first
	for i in range(3):
		var vis_col = 2 - i
		var start = i * pins_per_col
		if vis_col == target_col:
			final_target_idx = start + target_row
			break
			
	# Now convert that 'valid' index back to a global index in pinned_app_pkgs
	var new_idx = 0
	if final_target_idx < valid_pins.size():
		var target_pkg = valid_pins[final_target_idx]
		new_idx = pinned_app_pkgs.find(target_pkg)
	else:
		new_idx = pinned_app_pkgs.size() # Append to end
		
	# V14.53: CRITICAL REORDER SYNC
	# If we move an item forward, its removal from the list shifts the target index.
	# We must adjust for this to match the visual 'Gap' logic.
	if old_idx != -1 and old_idx < new_idx:
		new_idx -= 1
		
	print("Main: REORDER Debug -> Pkg: ", pkg, " | Old: ", old_idx, " | Target (Col: ", target_col, ", Row: ", target_row, ") -> New: ", new_idx)
	
	pinned_app_pkgs.pop_at(old_idx)
	pinned_app_pkgs.insert(new_idx, pkg)
	
	save_pinned_apps()
	refresh_launcher(true, true, "Icon Reordered")
	
	# CLEANUP: Ensure drag state is cleared
	if zone_managers.size() > 0:
		zone_managers[0].is_drag_active = false
		zone_managers[0].clear_drop_preview()
	refresh_launcher(false, false, "Pinned App Reorder")

func _handle_minimal_reorder(pkg, col, row):
	var apps = Settings.current_config.get("minimal_home_apps", [])
	var old_idx = apps.find(pkg)
	if old_idx == -1:
		refresh_launcher(false, false, "Minimal Mode Reorder (Not in List)")
		return
		
	# Slot Index Calculation (Matching spawn_apps)
	var slot_idx = (row * 3) + col
	var count = apps.size()
	
	# Target Logical Index = count - 1 - (5 - slot_idx)
	var new_idx = count - 1 - (5 - slot_idx)
	new_idx = clampi(new_idx, 0, count)
	
	if old_idx == new_idx or old_idx == new_idx - 1:
		refresh_launcher(false, false, "Minimal Mode Reorder (No Index Change)")
		return
		
	apps.pop_at(old_idx)
	if old_idx < new_idx: new_idx -= 1
	apps.insert(new_idx, pkg)
	
	Settings.current_config["minimal_home_apps"] = apps
	Settings.save_config()
	refresh_launcher(false, false, "Minimal Mode Reorder")

func show_context_menu(icon_node, pkg, label):
	if current_ctx_menu: current_ctx_menu.queue_free()
	var canvas = CanvasLayer.new()
	canvas.layer = 250 # Topmost (Above Search at 200)
	add_child(canvas)
	current_ctx_menu = canvas
	
	var screen_size = get_viewport_rect().size
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.3) # Lighter overlay
	bg.size = screen_size
	bg.gui_input.connect(func(event): if event is InputEventScreenTouch and event.pressed: close_context_menu())
	canvas.add_child(bg)
	
	
	# Dynamic Font Scaling
	var base_scale = screen_size.x / 1080.0
	var title_font = int(48 * base_scale)
	var btn_font = int(44 * base_scale)
	var btn_height = int(100 * base_scale)
	
	# Responsive Auto-Sizing Frame Container
	# Removed CenterContainer to allow manual positioning
	
	var frame = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.1) # Semi-transparent white tint
	style.set_corner_radius_all(30)
	style.set_content_margin_all(25) 
	style.shadow_size = 0 
	frame.add_theme_stylebox_override("panel", style)
	
	# Glass Effect for Context Menu (Shaderless Bypass)
	var blur_layer = TextureRect.new()
	blur_layer.name = "BlurLayer"
	blur_layer.texture = Settings.blurred_wallpaper_texture
	blur_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blur_layer.modulate.a = 0.8 # Deeper tint for context menu
	blur_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Connect to update if wallpaper changes while menu is open
	Settings.blurred_wallpaper_updated.connect(func():
		if is_instance_valid(blur_layer):
			blur_layer.texture = Settings.blurred_wallpaper_texture
	)
		
	frame.add_child(blur_layer)
	# Use clip_contents to ensure blur is restricted to the frame's rounded corners
	frame.clip_contents = true 
	canvas.add_child(frame)
	
	# Content Driven Size (No forced min width)
	# But ensure buttons aren't too tiny.
	
	var panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 2) 
	frame.add_child(panel)
	
	# Content
	var title = Label.new()
	title.text = label.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", title_font) 
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	panel.add_child(title)
	
	# Separator
	var sep = Control.new()
	sep.custom_minimum_size = Vector2(0, int(15 * base_scale))
	panel.add_child(sep)
	
	# Helper to create buttons
	var create_btn = func(text, callback):
		var btn = Button.new()
		btn.text = text
		btn.add_theme_font_size_override("font_size", btn_font) 
		btn.custom_minimum_size = Vector2(0, btn_height) 
		# Add horizontal padding to buttons so menu isn't too skinny
		# We can do this by adding spaces? Or just the panel margin handles it.
		# Let's set a small min width for the button itself if needed.
		btn.custom_minimum_size.x = int(300 * base_scale) 
		btn.flat = true 
		btn.focus_mode = Control.FOCUS_NONE # CRITICAL: Don't steal focus from Search/Keyboard
		btn.pressed.connect(callback)
		panel.add_child(btn)
		return btn

	# Helper to close search if open
	var fast_close_search = func():
		var search_layer = get_node_or_null("SearchLayer")
		if search_layer:
			for child in search_layer.get_children():
				if child.has_method("close_search"):
					child.close_search()

	# MODE ISOLATION: show only relevant pin option
	var is_minimal_mode = Settings.current_config.get("minimal_mode", false)
	
	# Premium Fade In for Menu (Increased to 0.4s)
	frame.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(frame, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	
	if is_minimal_mode:
		# MINIMAL MODE: Only Page-Specific Pining (Pin to Home)
		var minimal_home_apps = Settings.current_config.get("minimal_home_apps", [])
		if pkg in minimal_home_apps:
			create_btn.call("Unpin from Home", func(): remove_from_minimal_home(pkg); close_context_menu())
		else:
			create_btn.call("Pin to Home", func(): add_to_minimal_home(pkg); close_context_menu())
	else:
		# STANDARD MODE: Only Standard Page 1 Pinning (Pin App)
		create_btn.call("Pin App" if not pkg in pinned_app_pkgs else "Unpin App", func(): toggle_pin(pkg); close_context_menu())
	
	create_btn.call("App Info", func(): 
		if Engine.has_singleton("AppLoader"): Engine.get_singleton("AppLoader").open_app_info(pkg)
		close_context_menu()
		fast_close_search.call()
	)
	
	# Uninstall
	var uninstall_fn = func():
		print("Main: Uninstall button pressed for package: ", pkg)
		if Engine.has_singleton("AppLoader"):
			var loader = Engine.get_singleton("AppLoader")
			print("Main: Calling JNI uninstall_app (reverted) for: ", pkg)
			loader.uninstall_app(pkg)
		else:
			print("Main: AppLoader singleton NOT FOUND during uninstall")
		close_context_menu()
		# fast_close_search.call() # REMOVED: Prevent redirect to home on app drawer or search
		
	var un_btn = create_btn.call("Uninstall", uninstall_fn)
	un_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4)) 
	
	# POSITIONING LOGIC
	# Need to wait for layout to know size? 
	# Or just guess. 
	# Await frame to get size
	await get_tree().process_frame
	
	if not is_instance_valid(frame) or not is_instance_valid(icon_node): return
	
	var icon_rect = icon_node.get_global_rect()
	var menu_size = frame.size
	
	# Try to center horizontally on icon
	var pos_x = icon_rect.position.x + (icon_rect.size.x / 2.0) - (menu_size.x / 2.0)
	
	# Try to position below icon
	var pos_y = icon_rect.position.y + icon_rect.size.y + 10
	
	# Keyboard Awareness
	var keyboard_height = 0
	if Engine.has_singleton("AppLoader"):
		keyboard_height = Engine.get_singleton("AppLoader").get_keyboard_height()
		
	var bottom_limit = screen_size.y - 20
	if keyboard_height > 100:
		bottom_limit = screen_size.y - keyboard_height - 20
		
	# Clamp Y (Flip to top if no space below OR if covered by keyboard)
	if pos_y + menu_size.y > bottom_limit:
		# Flip to above
		pos_y = icon_rect.position.y - menu_size.y - 10
		
		# If acting smart, maybe clamp top too?
		if pos_y < 50: pos_y = 50 # Status bar safety
		
	frame.position = Vector2(pos_x, pos_y)



func init_minimal_home(app_list: Array):
	if Settings.current_config.get("minimal_home_initialized", false): return
	
	print("Main: Initializing Minimal Home grid for first run...")
	var most_used = []
	if Engine.has_singleton("AppLoader"):
		var json_str = Engine.get_singleton("AppLoader").fetch_usage_stats()
		if json_str != "" and json_str != "PERMISSION_DENIED":
			var json = JSON.new()
			if json.parse(json_str) == OK:
				var stats = json.data
				for s in stats:
					# VALIDATION: Only add if it's a valid launcher app found in current list
					var pkg = s.get("pkg")
					if _find_app_in_list(pkg, app_list):
						most_used.append(pkg)
						if most_used.size() >= 6: break
	
	# Fallback to current pins if no usage stats
	if most_used.is_empty():
		for pkg in pinned_app_pkgs:
			if not pkg.begins_with("virtual:"):
				if _find_app_in_list(pkg, app_list):
					most_used.append(pkg)
					if most_used.size() >= 6: break
	
	Settings.current_config["minimal_home_apps"] = most_used
	Settings.current_config["minimal_home_initialized"] = true
	Settings.save_config()
	print("Main: Minimal Home initialized with: ", most_used)

func add_to_minimal_home(pkg):
	var apps = Settings.current_config.get("minimal_home_apps", [])
	if pkg in apps: return
	
	# SELF-HEALING: Filter out invalid/uninstalled apps from the list before checking limit
	var valid_apps = []
	for p in apps:
		if _find_app_in_list(p, _cached_app_list):
			valid_apps.append(p)
	
	if valid_apps.size() >= 6:
		print("Main: Minimal Home limit reached (6)")
		if Engine.has_singleton("AppLoader"):
			Engine.get_singleton("AppLoader").make_toast("Minimal Home is full (Max 6 apps). Please unpin an existing app first.")
		
		# Persist the cleaned list anyway
		if valid_apps.size() != apps.size():
			Settings.current_config["minimal_home_apps"] = valid_apps
			Settings.save_config()
		return
	
	valid_apps.append(pkg)
	Settings.current_config["minimal_home_apps"] = valid_apps
	Settings.save_config()
	refresh_launcher(false, false, "Minimal Home Add")

func remove_from_minimal_home(pkg):
	var apps = Settings.current_config.get("minimal_home_apps", [])
	apps.erase(pkg)
	Settings.current_config["minimal_home_apps"] = apps
	Settings.save_config()
	refresh_launcher(false, false, "Minimal Home Remove")

func create_spacer(col_index, target_zone):
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(250, 380)
	spacer.size = Vector2(250, 380)
	spacer.set_meta("launcher_item", true)
	# Proxy the height method for ZoneManager
	spacer.set_script(load("res://scripts/Icon.gd")) 
	target_zone.register_icon(spacer, col_index)

func _find_app_in_list(pkg: String, list: Array):
	for a in list:
		if a.get("pkg") == pkg: return a
	return null

func close_context_menu():
	if current_ctx_menu:
		current_ctx_menu.queue_free()
		current_ctx_menu = null

func show_weather_settings(widget_node):
	print("Main: show_weather_settings() called for ", widget_node)
	if current_ctx_menu: close_context_menu()
	
	var settings_script = load("res://scripts/WeatherSettings.gd")
	if not settings_script:
		print("Main: ERROR - Failed to load WeatherSettings.gd")
		return

	var canvas = CanvasLayer.new()
	canvas.layer = 120
	add_child(canvas)
	current_ctx_menu = canvas # reuse the same variable for easy closing
	
	print("Main: Instantiating WeatherSettings object")
	var popup = settings_script.new()
	if popup:
		print("Main: WeatherSettings instantiated, adding to canvas")
		canvas.add_child(popup)
		if popup.has_method("open_at_widget"):
			popup.open_at_widget(widget_node)
			popup.settings_closed.connect(func():
				close_context_menu()
				if widget_node.has_method("fetch_weather"):
					widget_node.fetch_weather()
			)
	else:
		print("Main: ERROR - settings_script.new() returned null in Main context!")

func toggle_pin(pkg):
	if pkg in pinned_app_pkgs: pinned_app_pkgs.erase(pkg)
	else: pinned_app_pkgs.append(pkg)
	save_pinned_apps()
	refresh_launcher(false, false, "Toggle Pin")

func refresh_launcher(force_reset: bool = false, invalidate_cache: bool = false, reason: String = "Unknown"):
	if _is_refreshing: 
		print("Main: refresh_launcher SKIPPED (Already refreshing). Reason: ", reason)
		return
	_is_refreshing = true
	print("Main: refresh_launcher START. Reason: ", reason, " force_reset: ", force_reset, " invalidate_cache: ", invalidate_cache)
	
	# Block input and show busy indicator during layout rebuilds (e.g. icon pack change)
	set_busy(true)
	# 1. Close context menus
	if current_ctx_menu:
		current_ctx_menu.queue_free()
		current_ctx_menu = null

	# 2. Handle Scroll Position
	var saved_state = {}
	if not force_reset and is_instance_valid(zone_manager) and zone_manager.has_method("get_state") and zone_manager.column_count > 0:
		saved_state = zone_manager.get_state()
		
	# STAGGERED CLEANUP: Nuking 100+ nodes in one frame causes stutter.
	# We yield between zones to keep the main thread breathing.
	for zm in zone_managers:
		if is_instance_valid(zm):
			for child in zm.get_children():
				if child.has_meta("launcher_item"):
					child.remove_meta("launcher_item") # Prevent double-kill
					child.queue_free()
			await get_tree().process_frame
				
	# Also clear Main children (legacy safety)
	for child in get_children():
		if child.has_meta("launcher_item") or child.name == "UsageAccessBtn":
			child.queue_free()

	_temp_scroll_state = saved_state
	await get_apps(invalidate_cache)
	
var _temp_scroll_state = {}

	
# --- PAGE CONTAINER LOGIC ---
var page_container: Node2D
var zone_managers: Array = []
var current_page_index = 0
var page_width = 0.0

func setup_pages():
	if page_container: page_container.queue_free()
	zone_managers.clear()
	
	page_container = Node2D.new()
	add_child(page_container)
	
	page_width = get_viewport_rect().size.x
	
	# Create 2 Pages
	for i in range(2):
		# Reverted Mask Logic due to Blank Screen
		
		# ZONE MANAGER
		var zm = Node2D.new()
		zm.set_script(_zone_manager_script)
		zm.default_bg_opacity = current_config.get("bg_opacity", 0.5)
		zm.position = Vector2(i * page_width, 0) # RESTORE POSITION
		
		# Connect signals
		if i == 0:
			zm.is_home_zm = true
		
		# Connect signals
		zm.request_launch_app.connect(func(pkg): 
			if pkg == "virtual:settings":
				_open_settings_overlay()
			elif pkg == "virtual:uninstall":
				# This case is now legacy but kept for safety if any stray icons exist
				if Engine.has_singleton("AppLoader"):
					var app_loader = Engine.get_singleton("AppLoader")
					app_loader.vibrate(100)
					var my_pkg = app_loader.get_package_name()
					app_loader.uninstall_app(my_pkg)
			else:
				if Engine.has_singleton("AppLoader"):
					Engine.get_singleton("AppLoader").launch_app(pkg)
		)
		zm.request_open_app_info.connect(func(pkg): 
			if pkg != "virtual:settings":
				if Engine.has_singleton("AppLoader"):
					Engine.get_singleton("AppLoader").open_app_info(pkg)
		)
		zm.request_close_ctx_menu.connect(func():
			if current_ctx_menu:
				current_ctx_menu.queue_free()
				current_ctx_menu = null
		)
		
		page_container.add_child(zm) # Restore Parent
		zone_managers.append(zm)
		
	# Backwards compat for single-zone references
	zone_manager = zone_managers[0] 

var _page_drag_start = Vector2.ZERO
var _page_dragging = false

func _input(event):
	# V14.33: GLOBAL MULTI-TOUCH BLOCK (Index 0 only)
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if event.index > 0: return
		
	# DRAG BLOCK:
	if zone_managers.size() > 0 and zone_managers[0].is_drag_active:
		return
		
	# DRAWER BLOCK:
	if event is InputEventScreenTouch:
		if event.pressed:
			_page_drag_start = event.position
			_page_dragging = false # Wait for threshold
		else:
			if _page_dragging:
				_page_dragging = false
				var delta_x = event.position.x - _page_drag_start.x
				var delta_y = event.position.y - _page_drag_start.y
				
				# 1. SPECIAL CASE: Swipe from Right Edge -> Open Widget Drawer
				# (Only if Dynamic Positioning is ENABLED)
				if Settings.current_config.get("dynamic_widget_position", true):
					var screen_size = get_viewport_rect().size
					if delta_x < -150 and abs(delta_x) > abs(delta_y):
						if _page_drag_start.x > screen_size.x * 0.8:
							if _drawer: _drawer.snap_to_slot(3) # Open (Leftmost Slot)
							return
				
				# MINIMAL MODE VERTICAL BLOCK
				if Settings.current_config.get("minimal_mode", false):
					# Allow horizontal paging to proceed, but block vertical stuff if needed
					if abs(delta_y) > abs(delta_x) * 1.5:
						return
					
				# VERTICAL SWIPE CHECK (Prevent Page Snap/Reset on Vertical Scroll)
				if abs(delta_y) > abs(delta_x) and abs(delta_y) > 50:
					return
				
				if abs(delta_x) > 200: # Swipe Threshold
					if delta_x < 0 and current_page_index == 0:
						change_page(1)
					elif delta_x > 0 and current_page_index == 1:
						change_page(0)
					else:
						snap_to_page(current_page_index)
				else:
					snap_to_page(current_page_index)
					
	elif event is InputEventScreenDrag:
		if not _page_dragging:
			var delta_x = event.position.x - _page_drag_start.x
			var delta_y = event.position.y - _page_drag_start.y
			# V14.47: Only start paging if movement is predominantly horizontal and exceeds threshold
			if abs(delta_x) > 40.0 and abs(delta_x) > abs(delta_y) * 1.5:
				_page_dragging = true
				
		if _page_dragging:
			var delta_x = event.position.x - _page_drag_start.x
			var base_x = -current_page_index * page_width
			var target_x = base_x + delta_x
			
			# V14.37: Elastic Horizontal Stretch (Overscroll)
			# Apply 0.3x resistance when dragging past boundaries
			var max_x = 0.0
			var min_x = -(zone_managers.size() - 1) * page_width
			
			# V14.43: Higher Elasticity (0.5x) to show it's working
			if target_x > max_x:
				var overscroll = target_x - max_x
				target_x = max_x + (overscroll * 0.5) 
			elif target_x < min_x:
				var overscroll = target_x - min_x
				target_x = min_x + (overscroll * 0.5)
				
			page_container.position.x = target_x
			page_container.modulate.a = 1.0

func change_page(index: int):
	current_page_index = index
	snap_to_page(index)
	
	# Reset horizontal scroll in columns when switching pages
	for zm in zone_managers:
		if is_instance_valid(zm) and zm.has_method("reset_to_home"):
			zm.reset_to_home()
	
func snap_to_page(index: int):
	var target_x = -index * page_width
	var tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(page_container, "position:x", target_x, 0.4)
	
	# Fade Transitions for Pages (Subtle)
	for i in range(zone_managers.size()):
		var zm = zone_managers[i]
		if is_instance_valid(zm):
			# V14.42: Never hide pages entirely, just dim slightly when inactive
			var target_alpha = 1.0 if i == index else 0.8
			tween.tween_property(zm, "modulate:a", target_alpha, 0.4)
			
			# Ensure it's in a clean horizontal state if not the active page
			if i != index and zm.has_method("reset_to_home"):
				zm.reset_to_home()
	
	if _drawer:
		_drawer.set_page_index(index)


func setup_settings_button():
	if not is_instance_valid(_drawer): return
	print("Main: setup_settings_button running. Drawer children count: ", _drawer.get_child_count())
	
	var screen_size = get_viewport_rect().size
	var settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = "⚙"
	settings_btn.add_theme_font_size_override("font_size", 100) # Slightly smaller gear
	settings_btn.size = Vector2(160, 160) # Smaller touch target
	
	# Position relative to Drawer (centered horizontally in drawer width)
	var sidebar_width = screen_size.x / 4.0
	settings_btn.position = Vector2((sidebar_width - settings_btn.size.x) / 2.0, screen_size.y - 240) 
	settings_btn.flat = true
	settings_btn.pressed.connect(_open_settings_overlay)
	
	# Remove all background/focus rectangles
	var style_empty = StyleBoxEmpty.new()
	settings_btn.add_theme_stylebox_override("normal", style_empty)
	settings_btn.add_theme_stylebox_override("hover", style_empty)
	settings_btn.add_theme_stylebox_override("pressed", style_empty)
	settings_btn.add_theme_stylebox_override("focus", style_empty)
	settings_btn.focus_mode = Control.FOCUS_NONE  # Disable focus entirely
	
	# Attach to drawer so it moves
	_drawer.add_child(settings_btn)
	# Ensure it is rendered on top of widgets and background
	settings_btn.z_index = 5
	print("Main: Setup Settings Button Complete. Setting up Search...")

	setup_search_button(sidebar_width)
	print("Main: Setup Search Button Complete.")

func setup_search_button(sidebar_width):
	if not _drawer: return
	
	print("Main: setup_search_button running.")
	
	# Cleanup old search components
	var old_btn = _drawer.get_node_or_null("SearchButton")
	if old_btn: old_btn.queue_free()
	var old_bg = _drawer.get_node_or_null("SearchBarBg")
	if old_bg: old_bg.queue_free()
	var old_layer = get_node_or_null("SearchLayer")
	if old_layer: old_layer.queue_free()

	print("Main: Setting up Search Button with Yellow Bar")
	var search_btn = Button.new()
	search_btn.name = "SearchButton"
	
	var screen_size = get_viewport_rect().size
	var bar_y = screen_size.y - 350  # Moved down - between date and settings
	
	# === Yellow Bar Background (edge to edge, no rounded corners) ===
	var bar_bg = Panel.new()
	bar_bg.name = "SearchBarBg"
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.7, 0.6, 0.0, 1.0)  # Dark yellow/gold fill
	bar_style.border_width_left = 0
	bar_style.border_width_top = 3
	bar_style.border_width_right = 0
	bar_style.border_width_bottom = 3
	bar_style.border_color = Color(1.0, 0.85, 0.0, 1.0)  # Bright yellow border
	bar_style.set_corner_radius_all(0)  # NO rounded corners
	bar_bg.add_theme_stylebox_override("panel", bar_style)
	
	# Position bar - full width edge to edge
	bar_bg.size = Vector2(sidebar_width, 55)
	bar_bg.position = Vector2(0, bar_y)
	bar_bg.z_index = 5
	_drawer.add_child(bar_bg)
	
	# === Search Icon Button - SEPARATE from bar, overlapping ===
	var icon_size = 150  # 150px interactive area
	search_btn.size = Vector2(icon_size, icon_size)
	# Center the interactive area horizontally, and vertically on the bar
	search_btn.position = Vector2((sidebar_width - icon_size) / 2.0, bar_y - (icon_size - 55) / 2.0)
	search_btn.z_index = 10  # Above the bar
	
	# Transparent button background - Icon removed as per request
	var style = StyleBoxEmpty.new()
	search_btn.add_theme_stylebox_override("normal", style)
	search_btn.add_theme_stylebox_override("hover", style)
	search_btn.add_theme_stylebox_override("pressed", style)
	search_btn.add_theme_stylebox_override("focus", style)
	search_btn.focus_mode = Control.FOCUS_NONE
	search_btn.text = ""  # NO icon, NO emoji
	
	# Add button to drawer (NOT to bar_bg)
	_drawer.add_child(search_btn)
	
	print("Main: Search Button Area Created (Icon Hidden)")

	
	var search_script = load("res://scripts/SearchWidget.gd")
	if search_script:
		var search_overlay = search_script.new()
		var overlay_layer = CanvasLayer.new()
		overlay_layer.layer = 200
		overlay_layer.name = "SearchLayer"
		overlay_layer.add_to_group("suppress_drawer_input")
		add_child(overlay_layer)
		overlay_layer.add_child(search_overlay)
		
		# Connect button to open search
		search_btn.pressed.connect(func(): search_overlay.open_search())
		
		# Connect Context Menu Request
		search_overlay.request_context_menu.connect(show_context_menu)
		
		print("Main: Search overlay created")




func _open_settings_overlay():
	print("!!! Main: _open_settings_overlay TRIGGERED !!!")
	if has_node("SettingsCanvas"):
		print("Main: Settings already open, skipping.")
		return
		
	var settings_scn = load("res://Settings.tscn")
	print("Main: Loading Settings.tscn result: ", "OK" if settings_scn else "FAIL")
	
	if settings_scn:
		var settings_node = settings_scn.instantiate()
		print("Main: Instantiated settings_node: ", settings_node.name if settings_node else "NULL")
		settings_node.name = "SettingsOverlay"
		
		# Wrap in High Layer Canvas
		var overlay_layer = CanvasLayer.new()
		overlay_layer.layer = 201 # Absolute top
		overlay_layer.name = "SettingsCanvas"
		overlay_layer.add_to_group("suppress_drawer_input")
		overlay_layer.add_child(settings_node)
		print("Main: Added settings_node to SettingsCanvas (Layer 201)")
		
		# Connect Opacity Update
		if settings_node.has_signal("config_changed"):
			settings_node.config_changed.connect(func(k, v):
				if k == "bg_opacity":
					for zm in zone_managers:
						zm.update_all_opacities(v)
				elif k == "show_status_bar" or k == "show_nav_bar":
					current_config[k] = v # CRITICAL: Update local config
					apply_system_bars()
				elif k == "show_widget_drawer":
					current_config[k] = v
					setup_widget_drawer()  # Recreate or hide drawer (now also calls setup_settings_button)
				elif k == "active_icon_pack":
					current_config[k] = v
					if Engine.has_singleton("AppLoader"):
						Engine.get_singleton("AppLoader").set_active_icon_pack(v)
					call_deferred("refresh_launcher", true, true, "Config: Layout Swap")
				elif k == "icon_shape":
					current_config[k] = v
					if Engine.has_singleton("AppLoader"):
						Engine.get_singleton("AppLoader").set_active_icon_shape(v)
					refresh_launcher(true, true, "Config: Icon Pack Change")
				elif k == "dynamic_widget_position":
					current_config[k] = v
					snap_to_page(current_page_index) # Force snap to current page extreme
				elif k == "minimal_mode":
					current_config[k] = v
					refresh_launcher(true, true, "Config: Icon Shape Change")
				elif k.begins_with("show_") and k.ends_with("_widget"):
					current_config[k] = v
					setup_widget_drawer() # Rebuild to reflect visibility change
			)
		
		# COORDINATED CROSS-FADE: Listen for closing signal to trigger launcher fade-in
		if settings_node.has_signal("closing"):
			settings_node.closing.connect(fade_in_launcher)
		
		add_child(overlay_layer)
		
		# Listen for queue_free of the settings_node to cleanup the layer?
		# Or Settings.gd calls queue_free() on itself (Control).
		# We need the CanvasLayer to die too.
		# Better: Settings.gd should queue_free() its PARENT if parent is CanvasLayer.
		# Hack: Connect tree_exited of settings_node to queue_free the layer.
		settings_node.tree_exited.connect(func(): overlay_layer.queue_free())

func setup_background_layer():
	print("Main: setup_background_layer -> START")
	if wp_canvas: wp_canvas.queue_free()
	
	wp_canvas = CanvasLayer.new()
	wp_canvas.layer = -101 # Below EVERYTHING
	wp_canvas.name = "WallpaperLayer"
	add_child(wp_canvas)
	
	# 1. SAFETY SHIELD: Solid black background to prevent system launcher leaks
	var shield = ColorRect.new()
	shield.name = "SafetyShield"
	shield.color = Color(0, 0, 0, 1.0) # V4.63: Back to Opaque to prevent leaks
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wp_canvas.add_child(shield)
	
	# 1.5 MANAGED BACKGROUND: The high-res raw image
	managed_bg_rect = TextureRect.new()
	managed_bg_rect.name = "ManagedBG"
	managed_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	managed_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	managed_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	managed_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wp_canvas.add_child(managed_bg_rect)
	
	# 2. WALLPAPER TEXTURE: The actual blurred wallpaper
	wp_texture_rect = TextureRect.new()
	wp_texture_rect.name = "WallpaperTexture"
	wp_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wp_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wp_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wp_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if Settings.blurred_wallpaper_texture:
		wp_texture_rect.texture = Settings.blurred_wallpaper_texture
		
	wp_texture_rect.visible = false # V4.66: Start hidden, only used by components
	wp_canvas.add_child(wp_texture_rect)
	print("Main: background layer setup complete with Safety Shield.")

func base64_to_texture(base64_string: String) -> ImageTexture:
	if base64_string == "": return null
	var image = Image.new()
	var raw_data = Marshalls.base64_to_raw(base64_string)
	if raw_data.is_empty(): return null
	if image.load_png_from_buffer(raw_data) == OK or image.load_jpg_from_buffer(raw_data) == OK or image.load_webp_from_buffer(raw_data) == OK:
		return ImageTexture.create_from_image(image)
	return null

func fade_in_launcher():
	if is_instance_valid(page_container):
		print("Main: Fading in PageContainer...")
		var tween = create_tween()
		page_container.modulate.a = 0
		tween.tween_property(page_container, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func setup_busy_indicator():
	print("Main: setup_busy_indicator -> START")
	# High priority layer that captures all input
	busy_layer = CanvasLayer.new()
	busy_layer.layer = 300 # Above EVERYTHING (Settings=201, Search=200)
	busy_layer.name = "BusyLayer"
	busy_layer.visible = false # Hidden until needed
	add_child(busy_layer)
	
	# Darkening Shield
	var shield = ColorRect.new()
	shield.color = Color(0, 0, 0, 0.4) # Dim background
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IMPORTANT: Mouse filter must be STOP to block clicks reaching lower layers
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	busy_layer.add_child(shield)
	
	# Center Container for content
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	busy_layer.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	# Spinner-like text/emoji
	busy_spinner = Label.new()
	busy_spinner.text = "⚙" # Gear emoji
	busy_spinner.add_theme_font_size_override("font_size", 180)
	busy_spinner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Force pivot to center for rotation
	busy_spinner.pivot_offset = Vector2(90, 110) # Adjusted for label baseline
	vbox.add_child(busy_spinner)
	
	var status = Label.new()
	status.text = "Refining UI..."
	status.add_theme_font_size_override("font_size", 50)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status)
	print("Main: setup_busy_indicator -> END")

func set_busy(active: bool):
	if not busy_layer: return
	
	if active:
		if _busy_tween: 
			_busy_tween.kill()
		
		busy_layer.visible = true
		
		# V14.24: Enter Immersive Mode (Hide system bars) while busy
		if Engine.has_singleton("AppLoader"):
			Engine.get_singleton("AppLoader").set_system_bars_visibility(false, false)
			
		# Animate Spinner (simple rotation)
		_busy_tween = create_tween()
		_busy_tween.set_loops() # Infinite
		_busy_tween.tween_property(busy_spinner, "rotation", deg_to_rad(360), 1.5).from(0)
	else:
		# Tiny delay to ensure smooth transition once icons are visible
		get_tree().create_timer(0.2).timeout.connect(func():
			if is_instance_valid(busy_layer):
				busy_layer.visible = false
				
				if _busy_tween:
					_busy_tween.kill()
					_busy_tween = null
				
				# V14.24: Restore user's preferred system bar visibility
				apply_system_bars()
		)

