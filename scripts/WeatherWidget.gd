extends VBoxContainer

var label_temp: Label
var label_feels: Label
var label_desc: Label
var rect_icon: TextureRect
var http_weather: HTTPRequest

var press_timer: float = 0.0
var is_pressed: bool = false
const DRAG_CANCEL_THRESHOLD = 30.0
const LONG_PRESS_THRESHOLD = 0.5
var touch_start_pos = Vector2.ZERO
var last_update_time: int = 0
const REFRESH_INTERVAL = 300

# Debug Preview Mode
const DEBUG_PREVIEW_MODE = false  # SET TO true TO ENABLE PREVIEW
var _debug_icons = ["weather/sunny.png", "weather/cloudy.png", "weather/rain.png", "weather/snow.png", "weather/thunderstorm.png"]
var _debug_icon_index = 0
signal settings_requested(node)

func _ready():
	print("WeatherWidget: _ready() STARTED")
	alignment = BoxContainer.ALIGNMENT_BEGIN
	custom_minimum_size = Vector2(150, 0) # Auto-height
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	
	# 0. Settings Cog (Now relative to self)
	var cog_anchor = Control.new()
	cog_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cog_anchor)
	
	var cog = Label.new()
	cog.text = "⚙️"
	cog.add_theme_font_size_override("font_size", 55) 
	cog.modulate = Color(1, 1, 1, 0.4)
	cog.position = Vector2(170, 15) # Shifting right
	cog_anchor.add_child(cog)
	
	# 1.1 Weather Icon (Centered)
	var icon_center = CenterContainer.new()
	icon_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(icon_center)
	
	rect_icon = TextureRect.new()
	rect_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect_icon.custom_minimum_size = Vector2(160, 160)
	icon_center.add_child(rect_icon)
	
	# 1.2 Main Temperature
	label_temp = Label.new()
	label_temp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_temp.add_theme_font_size_override("font_size", 72)
	label_temp.text = "--°"
	add_child(label_temp)
	
	# 1.3 Feels Like
	label_feels = Label.new()
	label_feels.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_feels.add_theme_font_size_override("font_size", 32)
	label_feels.modulate = Color(1, 1, 1, 0.6)
	label_feels.text = "Feels like --°"
	add_child(label_feels)
	
	# 1.4 Description / City Name
	label_desc = Label.new()
	label_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_desc.add_theme_font_size_override("font_size", 42)
	label_desc.text = "Loading..." 
	label_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	label_desc.custom_minimum_size = Vector2(180, 0) # Narrower to force wrap
	add_child(label_desc)
	
	# 4. HTTPRequest
	http_weather = HTTPRequest.new()
	http_weather.request_completed.connect(_on_weather_received)
	add_child(http_weather)
	
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	if not DEBUG_PREVIEW_MODE:
		# Normal Mode - Fetch weather from API
		call_deferred("fetch_weather")
		
		# Refresh timer
		var refresh_timer = Timer.new()
		refresh_timer.wait_time = REFRESH_INTERVAL 
		refresh_timer.autostart = true
		refresh_timer.timeout.connect(fetch_weather)
		add_child(refresh_timer)
	else:
		# === DEBUG: Icon Preview Timer (30 seconds per icon) ===
		print("WeatherWidget: DEBUG PREVIEW MODE - Weather API disabled")
		var preview_timer = Timer.new()
		preview_timer.wait_time = 30.0
		preview_timer.autostart = true
		preview_timer.timeout.connect(_on_debug_timer_tick)
		add_child(preview_timer)
		
		# Load first icon immediately
		call_deferred("_load_debug_icon", _debug_icons[0])
	
	Settings.config_changed.connect(_on_settings_changed)
	
	print("WeatherWidget: _ready() COMPLETED")

func _on_settings_changed(key, _val):
	if key == "weather_city_data" or key == "weather_unit" or key == "all":
		fetch_weather()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		var now = Time.get_unix_time_from_system()
		if last_update_time > 0 and (now - last_update_time) > REFRESH_INTERVAL:
			print("WeatherWidget: Focus In - Weather stale, fetching new data")
			fetch_weather()


func _gui_input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start_pos = event.position
			is_pressed = true
			press_timer = 0.0
			accept_event()
		else:
			is_pressed = false
			accept_event()
			
	elif event is InputEventScreenDrag and is_pressed:
		var drag_dist = event.position.distance_to(touch_start_pos)
		if drag_dist > DRAG_CANCEL_THRESHOLD:
			is_pressed = false

func _process(delta):
	if is_pressed:
		press_timer += delta
		if press_timer >= LONG_PRESS_THRESHOLD:
			trigger_long_press()

func trigger_long_press():
	print("WeatherWidget: trigger_long_press() START")
	is_pressed = false
	
	# Signal parent drawer to stop its own long-press detection
	var p = get_parent()
	while p and not p.has_method("cancel_gestures"):
		p = p.get_parent()
	if p:
		p.call("cancel_gestures")
		print("WeatherWidget: Parent cancel_gestures() invoked")
		
	if Engine.has_singleton("AppLoader"):
		Engine.get_singleton("AppLoader").vibrate(60)
	
	print("WeatherWidget: Emitting settings_requested signal")
	settings_requested.emit(self)

func fetch_weather():
	# Update Timestamp
	last_update_time = Time.get_unix_time_from_system()

	var city_data = Settings.current_config.get("weather_city_data", {})
	var lat = city_data.get("lat", 9.8345)
	var lon = city_data.get("lon", 78.0933)
	var unit = Settings.current_config.get("weather_unit", "celsius")
	
	print("Weather: Fetching for ", lat, ",", lon)
	label_desc.text = "Loading: " + city_data.get("name", "Unknown")
	
	var url = "https://api.open-meteo.com/v1/forecast?latitude=%f&longitude=%f&current_weather=true" % [lat, lon]
	if unit == "fahrenheit":
		url += "&temperature_unit=fahrenheit"
	
	var err = http_weather.request(url)
	if err != OK:
		print("Weather: Request Failed to Start! Error: ", err)
	else:
		label_desc.text = "Loading..."

func _on_weather_received(result, response_code, _headers, body):
	# ... (Response parsing same as before) ...
	if response_code != 200:
		label_temp.text = "Err"
		return
		
	var json = JSON.new()
	var error = json.parse(body.get_string_from_utf8())
	if error == OK:
		var data = json.data
		var current = data.get("current_weather", {})
		var temp = current.get("temperature", 0)
		var apparent = current.get("apparent_temperature", temp) # Fallback if available
		var code = current.get("weathercode", 0)
		
		var unit = Settings.current_config.get("weather_unit", "celsius")
		var unit_sym = "°C" if unit == "celsius" else "°F"
		
		label_temp.text = str(round(temp)) + unit_sym
		label_feels.text = "Feels like " + str(round(apparent)) + unit_sym
		
		# Updating City Name (In case config changed)
		var city_data = Settings.current_config.get("weather_city_data", {})
		label_desc.text = city_data.get("name", "Unknown")
		
		# --- ICON LOADING (Deferred Safe) ---
		call_deferred("load_weather_icon", code)

func load_weather_icon(code):
	var icon_path = get_weather_icon_path(code)
	var tex = null
	
	print("Weather: Attempting to load icon: ", icon_path)
	
	# 1. Try JNI Base64 (proven working method)
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		var b64 = app_loader.call("loadAssetBase64", "assets/" + icon_path)
		print("Weather: JNI returned b64 len=", str(b64).length() if b64 else 0)
		
		if b64 != null and b64 != "":
			var bytes = Marshalls.base64_to_raw(b64)
			print("Weather: Decoded ", bytes.size(), " bytes")
			if bytes.size() > 0:
				var img = Image.new()
				var err = img.load_png_from_buffer(bytes)
				print("Weather: PNG parse result: ", err)
				if err == OK:
					tex = ImageTexture.create_from_image(img)
					print("Weather: Loaded JNI Icon: ", icon_path)
				else:
					# Try other formats
					err = img.load_jpg_from_buffer(bytes)
					if err == OK:
						tex = ImageTexture.create_from_image(img)
						print("Weather: Loaded JNI Icon (JPG): ", icon_path)
					else:
						err = img.load_webp_from_buffer(bytes)
						if err == OK:
							tex = ImageTexture.create_from_image(img)
							print("Weather: Loaded JNI Icon (WebP): ", icon_path)
	
	# 2. Try Resource (fallback)
	if not tex:
		var res = "res://assets/" + icon_path
		tex = load(res)
		if tex:
			print("Weather: Loaded Resource Icon: ", res)
			
	if tex:
		rect_icon.texture = tex
	else:
		print("Weather: Failed to load icon ", icon_path)
		rect_icon.texture = null

func get_weather_icon_path(code: int) -> String:
	var base = "weather/" 
	if code == 0: return base + "sunny.png"
	if code in [1, 2, 3]: return base + "cloudy.png"
	if code in [45, 48]: return base + "cloudy.png"
	if code in [51, 53, 55, 56, 57]: return base + "rain.png"
	if code in [61, 63, 65, 66, 67]: return base + "rain.png"
	if code in [71, 73, 75, 77]: return base + "snow.png"
	if code in [80, 81, 82]: return base + "rain.png"
	if code in [85, 86]: return base + "snow.png"
	if code in [95, 96, 99]: return base + "thunderstorm.png"
	return base + "sunny.png" 

func _on_debug_timer_tick():
	_debug_icon_index = (_debug_icon_index + 1) % _debug_icons.size()
	var icon_path = _debug_icons[_debug_icon_index]
	print("WeatherWidget: DEBUG - Timer tick, showing icon #", _debug_icon_index, ": ", icon_path)
	_load_debug_icon(icon_path)

func _load_debug_icon(icon_path: String):
	# Reuse the same loading logic as load_weather_icon
	print("WeatherWidget: DEBUG - Loading icon: ", icon_path)
	load_weather_icon_by_path(icon_path)


func load_weather_icon_by_path(icon_path: String):
	var tex = null
	
	# 1. Try JNI Base64
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		var b64 = app_loader.call("loadAssetBase64", "assets/" + icon_path)
		if b64 != null and b64 != "":
			var bytes = Marshalls.base64_to_raw(b64)
			if bytes.size() > 0:
				var img = Image.new()
				if img.load_png_from_buffer(bytes) == OK:
					tex = ImageTexture.create_from_image(img)
					print("WeatherWidget: DEBUG - JNI loaded: ", icon_path)
	
	# 2. Try Resource
	if not tex:
		var res = "res://assets/" + icon_path
		tex = load(res)
		if tex:
			print("WeatherWidget: DEBUG - Resource loaded: ", res)
	
	if tex:
		rect_icon.texture = tex
	else:
		print("WeatherWidget: DEBUG - FAILED to load: ", icon_path)
