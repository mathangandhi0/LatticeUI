func get_apps(invalidate_cache: bool = false):
	if _is_refreshing: return
	_is_refreshing = true
	
	if Engine.has_singleton("AppLoader"):
		var app_loader = Engine.get_singleton("AppLoader")
		if not app_loader.is_connected("package_changed", _on_package_changed):
			app_loader.connect("package_changed", _on_package_changed)
			
		if not app_loader.is_connected("home_pressed", _on_home_pressed):
			app_loader.connect("home_pressed", _on_home_pressed)
			
		if app_loader.has_method("update_system_ui"):
			app_loader.update_system_ui()
			
		if invalidate_cache or _cached_app_list.is_empty():
			if app_loader.has_method("get_installed_apps"):
				var json_str = app_loader.get_installed_apps()
				var json = JSON.new()
				if json.parse(json_str) == OK:
					var data = json.data
					_cached_app_list = data.get("apps", [])
					if data.has("battery_level"):
						Settings.battery_level = data.get("battery_level")
						Settings.is_charging = data.get("is_charging", false)
		
		spawn_apps(_cached_app_list)
	else:
		print("Main: Missing AppLoader singleton!")
	
	_is_refreshing = false
