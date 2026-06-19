extends CanvasLayer

signal closed

@onready var panel = $Control/Panel
@onready var grid = $Control/Panel/ScrollContainer/GridContainer

var is_open = false
var drawer_width = 800
var screen_size = Vector2.ZERO

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_open:
			close()
			get_viewport().set_input_as_handled()

func _ready():
	screen_size = get_viewport().get_visible_rect().size
	drawer_width = screen_size.x
	
	# Initial position: off-screen to the right
	$Control.position.x = screen_size.x
	
	$Control/Panel/Header/BackButton.pressed.connect(close)
	
	populate_apps()

func populate_apps():
	# Clear existing
	for child in grid.get_children():
		child.queue_free()
	
	if not Engine.has_singleton("AppLoader"):
		return
		
	var app_loader = Engine.get_singleton("AppLoader")
	var json_str = app_loader.get_installed_apps()
	var json = JSON.new()
	var error = json.parse(json_str)
	if error == OK:
		var app_list = json.data
		# Sort Alphabetically
		app_list.sort_custom(func(a, b): return a["name"].nocasecmp_to(b["name"]) < 0)
		for app in app_list:
			create_app_icon(app)

func create_app_icon(app_data):
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(250, 280)
	btn.flat = true
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(vbox)
	
	# Icon
	var tex_rect = TextureRect.new()
	var icon_base64 = app_data.get("icon", "")
	if icon_base64 != "":
		var image = Image.new()
		var err = image.load_png_from_buffer(Marshalls.base64_to_raw(icon_base64))
		if err == OK:
			tex_rect.texture = ImageTexture.create_from_image(image)
	
	tex_rect.custom_minimum_size = Vector2(140, 140)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(tex_rect)
	
	# Label
	var label = Label.new()
	label.text = app_data.get("name", "Unknown")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(label)
	
	btn.pressed.connect(func(): _on_app_pressed(app_data["pkg"]))
	grid.add_child(btn)

func _on_app_pressed(package_name):
	if Engine.has_singleton("AppLoader"):
		Engine.get_singleton("AppLoader").launch_app(package_name)
	close()

func open():
	if is_open: return
	is_open = true
	var tween = create_tween()
	tween.tween_property($Control, "position:x", screen_size.x - drawer_width, 0.3).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func close():
	if not is_open: return
	is_open = false
	var tween = create_tween()
	tween.tween_property($Control, "position:x", screen_size.x, 0.3).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	closed.emit()

func _input(event):
	if not is_open: return
	
	if event is InputEventScreenTouch:
		if event.pressed:
			# If touched outside the drawer (on the left side), close it
			if event.position.x < screen_size.x - drawer_width:
				close()
	
	if event is InputEventScreenDrag:
		# Detect left-to-right swipe to close
		if event.relative.x > 30 and event.velocity.x > 500:
			close()
	
	# Handle Android back button
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.keycode == KEY_BACK):
		close()
		get_viewport().set_input_as_handled()
