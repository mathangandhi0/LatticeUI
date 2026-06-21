extends Control

var package_name: String = ""
var app_label: String = ""
var custom_size: float = 0.0 # 0.0 means use default 250
var custom_shape_override: String = ""

signal long_pressed(node, pkg, label)
signal drag_started(node)
signal drag_ended(node, global_pos)
signal drag_moved(node, global_pos) # V14.51: Real-time tracking for visuals
signal request_launch(pkg)

var press_timer: float = 0.0
var is_pressed: bool = false
var is_dragging_item: bool = false
var has_triggered_menu: bool = false
var is_home: bool = false
var touch_start_pos = Vector2.ZERO
var active_touch_index: int = -1 # V14.32: Multi-touch isolation
var drag_offset = Vector2.ZERO # V14.44: Track where within icon the touch started

const DRAG_CANCEL_THRESHOLD = 30.0
const CLICK_DIST_THRESHOLD = 50.0

func _enter_tree():
	pass

func get_custom_height() -> float:
	return 380.0

func _ready():
	print("Icon: _ready() for ", app_label, " (pkg: ", package_name, ")")
	var screen_w = get_viewport_rect().size.x
	var col_w = screen_w / 4.0
	var total_size = Vector2(col_w, 380) # Dynamic width for 1px gaps
	var icon_size = Vector2(180, 180)
	var icon_pos = Vector2((col_w - 180) / 2.0, 40)
	var lbl_pos = Vector2(0, 235) # Slightly more breathing room
	var font_size = 34
	
	if custom_size > 0:
		total_size = Vector2(custom_size, custom_size + 130)
		var scale_ratio = custom_size / 250.0
		icon_size = Vector2(180 * scale_ratio, 180 * scale_ratio)
		var x_off = (custom_size - icon_size.x) / 2
		icon_pos = Vector2(x_off, x_off + 5)
		lbl_pos = Vector2(0, custom_size - 10)
		font_size = int(34 * scale_ratio)

	custom_minimum_size = total_size
	size = total_size
	mouse_filter = Control.MOUSE_FILTER_STOP 
	
	# Godot 4.7 Visual Optimization
	offset_transform_enabled = true
	offset_transform_pivot = total_size * 0.5
	
	# === DECOUPLE ANIMATION FROM POSITION ===
	# ZoneManager controls the 'position' of this root node every frame.
	# To allow entry animations without fighting the layout, we move all visual
	# elements into a main_container and animate THIS container instead.
	var main_container = Control.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main_container)
	
	# === ADD GHOST GLASS EFFECT ===
	var glass_panel = PanelContainer.new()
	glass_panel.name = "GlassBG"
	glass_panel.size = Vector2(total_size.x - 21.0, total_size.y - 21.0)
	glass_panel.position = Vector2(10.5, 10.5) 
	glass_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.1) # Tint for the glass
	style.set_corner_radius_all(15) # Match icon curves
	style.set_content_margin_all(2) 
	style.set_border_width_all(0) # No border here — drawn by overlay below
	glass_panel.add_theme_stylebox_override("panel", style)
	main_container.add_child(glass_panel)

	var blur_rect = TextureRect.new()
	blur_rect.name = "BlurLayer"
	blur_rect.texture = Settings.blurred_wallpaper_texture
	blur_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# V4.43: Shaderless Clipping
	glass_panel.clip_contents = true 
	glass_panel.add_child(blur_rect)
	
	# Connect for dynamic updates if wallpaper changes
	Settings.blurred_wallpaper_updated.connect(func():
		if blur_rect:
			# V4.76: Flicker Protection - Only fade if texture changed
			if blur_rect.texture == Settings.blurred_wallpaper_texture:
				return
				
			# V4.59: Smooth Fade-in Transition
			var tw = create_tween()
			blur_rect.modulate.a = 0
			blur_rect.texture = Settings.blurred_wallpaper_texture
			tw.tween_property(blur_rect, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	)
	
	# Premium Entry Animation
	main_container.modulate.a = 0
	var tween_in = create_tween().set_parallel(true)
	tween_in.tween_property(main_container, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	
	main_container.position.y = 30
	tween_in.tween_property(main_container, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# V4.73: Border Overlay — drawn on TOP of glass_panel so blur_rect never covers it
	var border_overlay = PanelContainer.new()
	border_overlay.name = "BorderOverlay"
	border_overlay.size = glass_panel.size
	border_overlay.position = glass_panel.position
	border_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0) # Fully transparent fill
	border_style.set_border_width_all(3)
	border_style.border_color = Color(1, 1, 1, 0.15)
	border_style.set_corner_radius_all(15)
	border_overlay.add_theme_stylebox_override("panel", border_style)
	main_container.add_child(border_overlay)
	
	print("Icon: Shaderless Blur added for ", app_label)
	
	var lbl = Label.new()
	lbl.name = "AppLabel"
	lbl.text = app_label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.position = lbl_pos
	lbl.size = Vector2(total_size.x, 150)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(lbl) # CHILD of container
	
	# Staggered JNI Loading: Add a small random delay 
	var delay = randf_range(0.01, 0.45) if not is_home else randf_range(0.01, 0.15)
	get_tree().create_timer(delay).timeout.connect(func(): load_icon_lazy(icon_size, icon_pos))


func load_icon_lazy(size_vec = Vector2(180, 180), pos_vec = Vector2(35, 35)):
	# V14.28: Memory Cache Check (Instant Population)
	# If we already have the Texture2D in RAM, apply it immediately.
	if Settings.icon_texture_cache.has(package_name):
		var cached_tex = Settings.icon_texture_cache[package_name]
		if is_instance_valid(cached_tex):
			apply_texture(cached_tex, size_vec, pos_vec)
			return

	# V14.28: Async Loading
	# We perform the JNI call and image parsing in a background thread
	# to ensure the main UI thread never stutters, even during high-load refreshes.
	WorkerThreadPool.add_task(func():
		if Engine.has_singleton("AppLoader"):
			var app_loader = Engine.get_singleton("AppLoader")
			var b64 = app_loader.get_app_icon(package_name)
			if b64 != "":
				var texture = base64_to_texture(b64)
				if texture:
					# Store in cache for future instant use
					Settings.icon_texture_cache[package_name] = texture
					# Apply to UI on the main thread
					call_deferred("apply_texture", texture, size_vec, pos_vec)
				else:
					print("Icon: Texture conversion failed for ", package_name)
			else:
				print("Icon: Plugin returned empty for ", package_name)
		else:
			print("Icon: AppLoader singleton missing")
	)

func apply_texture(texture: Texture2D, size_vec = Vector2(180, 180), pos_vec = Vector2(35, 35)):
	# Cleanup old nodes
	# Cleanup old nodes in both root and container
	for container in [self, get_node_or_null("MainContainer")]:
		if not container: continue
		var nodes_to_clean = ["AppIcon", "AdaptiveBg", "AdaptiveMask"]
		for node_name in nodes_to_clean:
			var old = container.get_node_or_null(node_name)
			if old: old.queue_free()
	
	# Simple uniform rendering for ALL icons
	# External apps: Already masked by AppLoader Java plugin
	# Internal apps: Use pre-shaped icon (app_logo.png with white background)
	var sprite = TextureRect.new()
	sprite.name = "AppIcon"
	sprite.texture = texture
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.size = size_vec
	sprite.position = pos_vec
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mc = get_node_or_null("MainContainer")
	if mc:
		mc.add_child(sprite)
		mc.move_child(sprite, 1) # Behind label
	else:
		add_child(sprite)
		move_child(sprite, 1)

func base64_to_texture(base64_string: String) -> ImageTexture:
	if base64_string == "": return null
	var image = Image.new()
	var raw_data = Marshalls.base64_to_raw(base64_string)
	if raw_data.is_empty(): return null
	if image.load_png_from_buffer(raw_data) == OK or image.load_jpg_from_buffer(raw_data) == OK or image.load_webp_from_buffer(raw_data) == OK:
		return ImageTexture.create_from_image(image)
	return null

func load_internal_icon_as_base64() -> String:
	# Load app_logo.png (or fallback to icon.png) and return as base64
	# This is used to pass internal icons to AppLoader.mask_bitmap_base64()
	var paths_to_try = ["res://app_logo.png", "res://icon.png"]
	
	for path in paths_to_try:
		# Try JNI AssetManager first (most reliable on Android)
		if Engine.has_singleton("AppLoader"):
			var app_loader = Engine.get_singleton("AppLoader")
			var jni_path = path.replace("res://", "")
			var b64 = app_loader.call("loadAssetBase64", jni_path)
			if b64 != null and b64 != "":
				print("Icon: Loaded internal icon via JNI: ", jni_path)
				return b64
		
		# Try standard Godot load as fallback
		var tex = load(path)
		if tex:
			var img = tex.get_image()
			if img:
				var buffer = img.save_png_to_buffer()
				if buffer.size() > 0:
					print("Icon: Loaded internal icon via Godot load: ", path)
					return Marshalls.raw_to_base64(buffer)
	
	print("Icon: Failed to load any internal icon as base64")
	return ""

func _gui_input(event):
	# V14.33: STRICT MULTI-TOUCH BLOCK
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if event.index > 0: return
		
	if event is InputEventScreenTouch:
		if event.pressed:
			# V14.32: Only respond if not already pressed by another finger
			if active_touch_index != -1: return
			
			active_touch_index = event.index
			touch_start_pos = event.position
			is_pressed = true
			press_timer = 0.0
			is_dragging_item = false
			has_triggered_menu = false
			
			var press_tween = create_tween()
			press_tween.tween_property(self, "offset_transform_scale", Vector2(0.95, 0.95), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			
			accept_event()
		elif not event.pressed:
			if event.index != active_touch_index: return
			
			var drag_dist = event.position.distance_to(touch_start_pos)
			var was_p = is_pressed
			var was_dragging = is_dragging_item
			
			active_touch_index = -1
			is_pressed = false
			is_dragging_item = false
			var release_tween = create_tween()
			release_tween.tween_property(self, "offset_transform_scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			modulate.a = 1.0
			
			if was_dragging:
				drag_ended.emit(self, get_global_mouse_position())
				accept_event()
				return

			# Hardcoded click check (0.6s)
			if was_p and drag_dist < CLICK_DIST_THRESHOLD and press_timer < 0.6:
				if not _is_scroll_active():
					launch_app()
				else:
					print("Icon: Launch BLOCKED due to active scroll")
			accept_event()
			
	elif event is InputEventScreenDrag:
		if is_dragging_item:
			# Update position while dragging to follow finger
			# V14.44: Use drag_offset to prevent "centering" jump
			global_position = get_global_mouse_position() - drag_offset
			drag_moved.emit(self, get_global_mouse_position())
			accept_event()
		elif is_pressed and event.index == active_touch_index:
			var drag_dist = event.position.distance_to(touch_start_pos)
			if drag_dist > DRAG_CANCEL_THRESHOLD:
				active_touch_index = -1
				is_pressed = false

func _is_scroll_active() -> bool:
	# 1. Check parent ZoneManager (Internal column scroll)
	var p = get_parent()
	while p:
		if p.has_method("is_any_drag_active"):
			if p.call("is_any_drag_active"): return true
		p = p.get_parent()
	
	# 2. Check Global Main (Paging scroll)
	var main = get_tree().root.get_node_or_null("Main")
	if main and main.get("_page_dragging"):
		return true
		
	return false

func _process(delta):
	# V4.45: SHADERLESS ALIGNMENT (Merged)
	var layer = get_node_or_null("MainContainer/GlassBG/BlurLayer")
	if layer:
		layer.global_position = Vector2.ZERO
		layer.size = get_viewport_rect().size
		
	if is_pressed and not is_dragging_item:
		press_timer += delta
		
		# Threshold 1: Context Menu (0.4s)
		if press_timer >= 0.6 and not has_triggered_menu:
			has_triggered_menu = true
			trigger_long_press()
		
		# Threshold 2: Drag Initiation (0.8s total)
		if press_timer >= 1.2 and is_home:
			is_dragging_item = true
			is_pressed = false # Stop the timer/click logic
			
			# V14.44: Capture drag offset relative to global touch
			drag_offset = get_global_mouse_position() - global_position
			# Visual Lift
			var tween = create_tween()
			tween.tween_property(self, "offset_transform_scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			modulate.a = 0.7
			z_index = 100 # Draw on top
			
			if Engine.has_singleton("AppLoader"):
				Engine.get_singleton("AppLoader").vibrate(80) # Stronger vibration for drag
				
			drag_started.emit(self)

func trigger_long_press():
	# Note: is_pressed remains true to allow Step 2 (Drag)
	# highlight_rect.visible = false # Keep it highlighted while holding? 
	if Engine.has_singleton("AppLoader"):
		Engine.get_singleton("AppLoader").vibrate(60)
	long_pressed.emit(self, package_name, app_label)

func launch_app():
	request_launch.emit(package_name)

func set_header(_t): pass

func load_external_texture(path: String) -> Texture2D:
	# Method 1: Force Direct File Load (Bypass Cache for local dev updates)
	# This fixes the issue where replacing icon.png doesn't update in-game
	if path.begins_with("res://"):
		var global_path = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(global_path):
			var img = Image.load_from_file(global_path)
			if img:
				print("Icon: Loaded global file (Bypass Cache): ", global_path)
				return ImageTexture.create_from_image(img)
	
	# Method 2: Standard Godot load (works with imported .ctex files)
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
	
	# Method 3: Try without res:// prefix
	var alt_path = path.replace("res://", "")
	tex = load(alt_path)
	if tex:
		print("Main: Loaded texture via alt path: ", alt_path)
		return tex
	
	# Method 4: JNI AssetManager for raw PNG files (non-imported)
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		var jni_path = path.replace("res://", "")
		
		print("Main: Trying JNI load for: ", jni_path)
		
		# Try Base64 transfer - call directly without has_method check
		var b64 = app_loader.call("loadAssetBase64", jni_path)
		
		if b64 != null and b64 != "":
			var bytes = Marshalls.base64_to_raw(b64)
			if bytes.size() > 0:
				var jni_img = Image.new()
				var err = jni_img.load_png_from_buffer(bytes)
				if err == OK:
					return ImageTexture.create_from_image(jni_img)
					
	return null
