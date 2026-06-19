extends Node2D

var _text: String = ""
var _icon: Texture2D = null

func get_custom_height() -> float:
	return 200.0

func _init(text: String = "", icon_texture: Texture2D = null):
	_text = text
	_icon = icon_texture

func _ready():
	# Construct visuals when entering tree
	if _icon:
		var sprite = Sprite2D.new()
		sprite.texture = _icon
		# Scale to 120px wide
		var sw = _icon.get_width()
		if sw > 0:
			var s = 120.0 / sw
			sprite.scale = Vector2(s, s)
		sprite.position = Vector2(0, 0) # Centered in 200px slot
		add_child(sprite)
		print("CategoryHeader: Rendered Icon for '", _text, "'")
	elif _text != "":
		var label = Label.new()
		# Vertical Text logic
		var vt = ""
		for i in range(_text.length()):
			vt += _text[i].to_upper()
			if i < _text.length() - 1: vt += "\n"
		
		label.text = vt
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# For Node2D, we center based on half width/height
		label.size = Vector2(300, 160)
		label.position = Vector2(-150, 0) # Centered in 200px slot
		label.add_theme_font_size_override("font_size", 70)
		label.add_theme_color_override("font_color", Color.WHITE)
		add_child(label)
		print("CategoryHeader: Rendered Text: ", _text)
	else:
		print("CategoryHeader: Empty header initialized")
