extends VBoxContainer

var label_month: Label
var label_day: Label
var label_weekday: Label

func _ready():
	# Configure VBox
	alignment = BoxContainer.ALIGNMENT_CENTER
	# Standardize width/height for sidebar
	custom_minimum_size = Vector2(250, 300)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", -10)
	
	# Month (JAN)
	label_month = Label.new()
	label_month.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_month.add_theme_font_size_override("font_size", 50) 
	label_month.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3)) 
	add_child(label_month)
	
	# Day (18)
	label_day = Label.new()
	label_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_day.add_theme_font_size_override("font_size", 120) # Adjusted for sidebar
	label_day.add_theme_color_override("font_color", Color.WHITE)
	add_child(label_day)
	
	# Weekday (SUN)
	label_weekday = Label.new()
	label_weekday.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_weekday.add_theme_font_size_override("font_size", 50)
	label_weekday.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9)) 
	add_child(label_weekday)
	
	# Initial Update
	update_date()
	
	# Timer
	var timer = Timer.new()
	timer.wait_time = 60.0
	timer.autostart = true
	timer.timeout.connect(update_date)
	add_child(timer)

func update_date():
	var time = Time.get_datetime_dict_from_system()
	
	# Month Map
	var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	label_month.text = months[time.month - 1]
	
	# Day
	label_day.text = str(time.day).pad_zeros(2)
	
	# Weekday Map
	var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
	# Godot: weekday 0 = Sunday (Check docs? Usually 1=Monday or 0=Sunday)
	# Time.get_datetime_dict_from_system() -> "weekday" (0 = Sunday, 1 = Monday... 6 = Saturday)
	label_weekday.text = days[time.weekday]
