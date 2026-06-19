extends Node

signal config_changed(key, value)
signal blurred_wallpaper_updated

var blurred_wallpaper_texture: Texture2D = null

# V14.28: Memory Cache for Texture2D objects.
# This eliminates the need to decode Base64 and create new textures on every refresh.
var icon_texture_cache: Dictionary = {}

func clear_texture_cache(pkg: String = ""):
	if pkg == "":
		print("Settings: Full Texture Cache Cleared")
		icon_texture_cache.clear()
	else:
		if icon_texture_cache.has(pkg):
			print("Settings: Selective Texture Cache Clear: ", pkg)
			icon_texture_cache.erase(pkg)

const DEFAULT_CONFIG = {
	"max_fps": 0,
	"bg_opacity": 0.0,
	"active_icon_pack": "",
	"icon_shape": "circle",
	"weather_city_data": {
		"name": "London",
		"lat": 51.5074,
		"lon": -0.1278
	},
	"weather_unit": "celsius",
	"show_status_bar": false,
	"show_nav_bar": true,
	"show_widget_drawer": true,
	"show_clock_widget": true,
	"show_battery_widget": true,
	"show_weather_widget": true,
	"show_date_widget": true,
	"dynamic_widget_position": false,
	"drawer_palette_index": 0,
	"minimal_mode": false,
	"minimal_home_apps": [],
	"minimal_home_initialized": false,
	"blur_amount": 100.0
}

var current_config = DEFAULT_CONFIG.duplicate(true)

func reset_to_defaults():
	current_config = DEFAULT_CONFIG.duplicate(true)
	save_config()
	emit_signal("config_changed", "all", null)


# System Status (Updated via AppLoader piggyback)
# System Status (Updated via AppLoader piggyback)
var battery_level: int = 100
var is_charging: bool = false
var system_long_press_time: float = 0.4 # Default to 400ms

func is_initialized():
	return true

func _ready():
	load_config()

func load_config():
	if FileAccess.file_exists("user://config.json"):
		var f = FileAccess.open("user://config.json", FileAccess.READ)
		var json = JSON.parse_string(f.get_as_text())
		if json:
			for key in json:
				current_config[key] = json[key]

func save_config():
	var f = FileAccess.open("user://config.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(current_config))
