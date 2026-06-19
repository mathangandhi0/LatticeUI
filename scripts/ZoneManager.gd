extends Node2D

signal request_launch_app(pkg)
signal request_open_app_info(pkg)
signal request_close_ctx_menu # Start Auto-Scroll -> Close Menu

var active_drawer_ref: Control = null
var column_count = 0
var is_home_zm = false # NEW: Track if this ZM is for the Home Screen
var is_drag_active = false # NEW: Disable scroll during icon drag

var icons_by_zone = [] # Array of Arrays
var screen_width = 0.0
var screen_height = 0.0
var col_wrappers = [] # Array of Node2Ds for Icons
var preview_target = {} # V14.51: { "column": int, "index": int }
var preview_shift_weights = [] # Lerped weights [0.0 - 1.0] for gap opening
var home_h_offset = 0.0 # Standard centered position
var default_bg_opacity = 0.0 # Disabled per user request


const GLASS_PALETTE = [
	Color(0.2, 0.3, 0.7, 0.7),  # Vibrant Blue
	Color(0.7, 0.2, 0.3, 0.7),  # Vibrant Rose
	Color(0.2, 0.6, 0.3, 0.7),  # Vibrant Emerald
	Color(0.4, 0.4, 0.4, 0.7),  # Bold Grey
	Color(0.7, 0.5, 0.1, 0.7),  # Vibrant Gold
	Color(0.1, 0.6, 0.7, 0.7)   # Vibrant Azure
]

# === PHYSICS CONFIG (FINAL POLISH - SNAPBY & BOOST) ===
# Horizontal
var h_offset = 0.0
var h_velocity = 0.0
const H_DAMPING_GLIDE = 0.96 # Sharper stop (reverted from 0.99)
const H_SCROLL_SENSITIVITY = 1.0 # Reduced from 1.2
const DRAG_THRESHOLD = 40.0 # Increased from 20.0 to fix jitter

# Vertical
var col_offsets = [] 
var col_velocities = [] 
const V_DAMPING = 0.95 # Higher Friction (Stops faster)
const V_SCROLL_SENSITIVITY = 1.2 # Direct Tracking (Near 1:1)
const V_FLING_BOOST = 1.5 # Reduced boost since we track velocity directly

# Interaction Constants
const ICON_SPACING = 380.0 # Vertical spacing (Refined)
const TOP_PADDING = 70.0

# Gesture State
var touch_start_pos = Vector2.ZERO
var is_dragging = false
var last_drag_pos = Vector2.ZERO
var last_drag_time = 0
var target_h_offset = 0.0
var is_horiz_dragging = false
var is_vert_dragging = false

var is_sleeping: bool = false
var time_since_input: float = 0.0
var active_touch_index: int = -1 # V14.31: Multi-touch fix

func _ready():
	print("ZoneManager: _ready() called. Name: ", name)
	screen_width = get_viewport_rect().size.x
	screen_height = get_viewport_rect().size.y
	print("ZoneManager: Screen Size: ", screen_width, "x", screen_height)
	wake_up()

func reinit_columns(count: int):
	print("ZoneManager: reinit_columns(", count, ") called for ", name)
	column_count = count
	icons_by_zone.clear()
	col_offsets.clear()
	col_velocities.clear()
	
	for i in range(column_count):
		icons_by_zone.append([])
		col_offsets.append(0.0)
		col_velocities.append(0.0)
	# 2. Handle Alignment
	var col_width = screen_width / 4.0
	if is_home_zm:
		# V14.45: Always left-align Home columns to stay out of Widget Drawer's slice (Slot 3)
		home_h_offset = 0.0
	else:
		home_h_offset = (4 - column_count) * col_width * 0.5
		
	h_offset = home_h_offset
	target_h_offset = h_offset
	h_velocity = 0.0
	
	# Create Wrappers
	for w in col_wrappers: w.queue_free()
	col_wrappers.clear()
	
	for i in range(column_count):
		col_offsets.append(0.0)
		preview_shift_weights.append(0.0)
		# Wrapper
		var wrapper = Node2D.new()
		add_child(wrapper)
		col_wrappers.append(wrapper)
		
	wake_up()

var pinned_col_index = -1 
var pinned_zoom_strength = 1.0
var transform_col_touch_index = -1
var pinned_touch_timer = 0.0

func set_pinned_column_index(idx: int):
	pinned_col_index = idx

func update_all_opacities(alpha: float):
	default_bg_opacity = alpha
	wake_up()

func register_icon(icon: CanvasItem, column_index: int):
	# Ensure wrappers exist
	if column_index < col_wrappers.size():
		# Parent to the specific column wrapper
		if icon.get_parent(): icon.get_parent().remove_child(icon)
		col_wrappers[column_index].add_child(icon)
		# print("ZM: Registered Icon in Col ", column_index)
		
		# Keep legacy array for safety if referenced elsewhere
		if column_index < icons_by_zone.size():
			icons_by_zone[column_index].append(icon)
		
		icon.visible = true
		
		# Connect Icon signals to ZoneManager relays
		if icon.has_signal("request_launch"):
			if not icon.request_launch.is_connected(func(pkg): request_launch_app.emit(pkg)):
				icon.request_launch.connect(func(pkg): request_launch_app.emit(pkg))

func scroll_to_column(index: int):
	if index < 0 or index >= column_count: return
	
	var col_width = screen_width / 4.0
	# Standard Left Alignment:
	target_h_offset = - (index * col_width) 
	
	h_velocity = 0.0
	for i in range(column_count):
		col_velocities[i] = 0.0
	wake_up()

func reset_to_home():
	target_h_offset = home_h_offset
	h_velocity = 0.0
	wake_up()

func scroll_to_end():
	if column_count > 0:
		var index = column_count - 1
		var col_width = screen_width / 4.0
		var total_width = column_count * col_width
		var raw_x = (index * col_width) + h_offset
		var wrap_buffer = col_width * 2.0
		var wrapped_x = fposmod(raw_x + wrap_buffer, total_width) - wrap_buffer
		var target_x = screen_width - col_width
		var dist = abs(wrapped_x - target_x)
		
		var v_reset_needed = false
		for i in range(column_count):
			if abs(col_offsets[i]) > 1.0: v_reset_needed = true
		
		if dist < 40.0 and abs(h_velocity) < 50.0 and not v_reset_needed:
			return
		
		scroll_to_column(index)
		
	for i in range(column_count):
		col_offsets[i] = 0.0
		col_velocities[i] = 0.0

var vertical_return_active = false

func reset_vertical_offsets(smooth: bool = true):
	if not smooth:
		for i in range(column_count):
			col_offsets[i] = 0.0
			col_velocities[i] = 0.0
		vertical_return_active = false
		wake_up()
	else:
		# Trigger smooth return in _process
		vertical_return_active = true
		wake_up()

func wake_up():
	# Always enforce High Performance on wake
	OS.low_processor_usage_mode = false 
	if Engine.max_fps < 120:
		Engine.max_fps = 120
		
	is_sleeping = false
	time_since_input = 0.0
	set_process(true)

func is_any_drag_active() -> bool:
	return is_dragging or is_horiz_dragging or is_vert_dragging

func _input(event):
	# V14.33: STRICT MULTI-TOUCH BLOCK
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if event.index > 0: return
		
	if not is_visible_in_tree(): return # V14.32: Ignore input if hidden
	if is_drag_active: return # Block scrolling during icon drag
	
	if event is InputEventScreenTouch:
		if event.pressed:
			# V14.31: Only capture the FIRST finger for scrolling
			if active_touch_index != -1: return 
			
			# FIX V4.24: INPUT ISOLATION
			# Check if touch is on a menu, settings box, or other overlay
			var hovered = get_viewport().gui_get_hovered_control()
			if hovered:
				if not _is_launcher_item(hovered):
					# print("ZM: Input BLOCKED by UI: ", hovered.name)
					return # Stand still if interacting with UI
					
			active_touch_index = event.index
			touch_start_pos = event.position
			last_drag_pos = event.position
			is_dragging = true
			
			# Cancel any smooth return animation
			vertical_return_active = false
			
			# Identify touched column
			var local_pos = make_input_local(event).position
			var col_width = screen_width / 4.0
			transform_col_touch_index = -1
			
			if column_count > 0:
				for i in range(column_count):
					# In standard layout, wrapped_x is just the local offset
					var wrapped_x = (i * col_width) + h_offset
					# Add epsilon to width to ensure edges are responsive
					if local_pos.x >= wrapped_x - 5.0 and local_pos.x < wrapped_x + col_width + 5.0:
						transform_col_touch_index = i
						break
			
			h_velocity = 0.0
			target_h_offset = h_offset
			is_horiz_dragging = false
			is_vert_dragging = false
			for i in range(column_count):
				col_velocities[i] = 0.0
				
			wake_up()
		else:
			if event.index == active_touch_index:
				active_touch_index = -1
				is_dragging = false
				# Stale check
				var now = Time.get_ticks_msec()
				if now - last_drag_time > 100:
					h_velocity = 0.0
					for i in range(column_count):
						col_velocities[i] = 0.0

	elif event is InputEventScreenDrag and is_dragging and event.index == active_touch_index:
		wake_up()
		last_drag_time = Time.get_ticks_msec()

		var delta_move = event.position - last_drag_pos
		last_drag_pos = event.position
		
		# Separate Axis Logic with Deadzone
		var total_delta = event.position - touch_start_pos
		
		if not is_horiz_dragging and not is_vert_dragging:
			# MINIMAL MODE BLOCK (Home Only)
			if is_home_zm and Settings.current_config.get("minimal_mode", false):
				return
				
			# DYNAMIC THRESHOLD: Be more forgiving on Pinned Column to allow Auto-Scroll
			var current_threshold = DRAG_THRESHOLD
			if transform_col_touch_index == pinned_col_index:
				current_threshold = 80.0 # Double threshold to absorb jitter while holding
			
			if abs(total_delta.x) > current_threshold:
				is_horiz_dragging = true # Re-enabled per user request
				pass
			elif abs(total_delta.y) > current_threshold:
				is_vert_dragging = true
		
		if is_horiz_dragging:
			# V14.42: LOCKED HORIZONTAL SCROLL
			# We detect the gesture to block taps/launching, but do NOT move 
			# the columns internally. Positioning is handled by Main.gd paging.
			pass
		elif is_vert_dragging:
			var local_drag_pos = make_input_local(event).position
			var col_width = screen_width / 4.0
			for i in range(column_count):
				var wrapped_x = (i * col_width) + h_offset
				
				if local_drag_pos.x >= wrapped_x - 5.0 and local_drag_pos.x < wrapped_x + col_width + 5.0:
					# DIRECT MANIPULATION (Follow Finger)
					
					# Standard Vertical Scroll (Recents or Drawer)
					col_offsets[i] += delta_move.y * V_SCROLL_SENSITIVITY
					
					# CAPTURE VELOCITY FOR FLING (Momentum on release)
					if event.velocity != Vector2.ZERO:
						col_velocities[i] = event.velocity.y * V_FLING_BOOST
					else:
						col_velocities[i] = delta_move.y * 60.0

func _process(delta):
	# 1. OPTIMIZATION
	screen_height = get_viewport_rect().size.y
	
	# MINIMAL MODE: Force bottom positioning (Home Only)
	var effective_top_padding = TOP_PADDING
	if is_home_zm and Settings.current_config.get("minimal_mode", false):
		# We assume 2 rows. 2 * 400px = 800px.
		# start_y + 760 = height - 40
		# start_y = height - 800
		effective_top_padding = screen_height - 800.0 
		col_offsets = [0.0, 0.0, 0.0, 0.0] # Lock offsets
		col_velocities = [0.0, 0.0, 0.0, 0.0]
	
	if not is_dragging:
		time_since_input += delta
		
		# SMOOTH SYNC: Always lerp h_offset to target_h_offset when not dragging
		# This ensures that programmatic snaps (Page change) are smooth.
		h_offset = lerp(h_offset, target_h_offset, delta * 10.0)
		
		h_velocity = 0.0
		# h_offset = lerp(h_offset, target_h_offset, 0.2) # Soft sync if needed, or rely on scroll_to_column
		
		var max_v = 0.0
		for v in col_velocities:
			max_v = max(max_v, abs(v))
			
		if abs(h_velocity) < 5.0 and max_v < 5.0 and time_since_input > 1.0:
			if not is_sleeping:
				is_sleeping = true
				set_process(false)
				OS.low_processor_usage_mode = true # Low Power Mode when idle
			return
			
		# h_velocity *= H_DAMPING_GLIDE
		# if abs(h_velocity) < 30.0: h_velocity = 0.0 # Stop lazy crawl
		# target_h_offset += h_velocity * delta
		# h_offset = lerp(h_offset, target_h_offset, 0.4) # Smooth glide
		# h_offset = lerp(h_offset, target_h_offset, 0.4) # Smooth glide
		pass
		
		for i in range(column_count):
			col_velocities[i] *= V_DAMPING
			col_offsets[i] += col_velocities[i] * delta
			
			
			# Infinite Scroll: No clamps.
				
	else:
		# Active Drag Smoothing
		h_offset = lerp(h_offset, target_h_offset, 0.45)
		
	# SMOOTH VERTICAL RETURN (Home Button)
	if vertical_return_active and not is_dragging:
		var still_moving = false
		for i in range(column_count):
			col_offsets[i] = lerp(col_offsets[i], 0.0, delta * 8.0)
			if abs(col_offsets[i]) > 1.0:
				still_moving = true
			else:
				col_offsets[i] = 0.0 # Snap when close
		
		
		if not still_moving:
			vertical_return_active = false # Finished

	# RENDER (BUFFERED WRAP)
	var col_width = screen_width / 4.0
	var total_width = column_count * col_width
	if total_width < 1: return 
	
			
	
	# STANDARD COLUMN LOOP (Process all columns vertically)
	for i in range(column_count):
		# V14.51: Smoothly lerp the gap weight for this column
		var target_weight = 1.0 if (preview_target.get("column", -1) == i) else 0.0
		preview_shift_weights[i] = lerp(preview_shift_weights[i], target_weight, delta * 15.0)
		
		# X Calc (Offset seam)
		var base_x = (i * col_width)
		var raw_x = base_x + h_offset
		var wrapped_x = raw_x
		
		# Strict Culling
		var is_col_visible = wrapped_x > -col_width and wrapped_x < total_width + col_width 
		# RELAXED SCREEN BOUNDS (Prevent disappearing during overscroll)
		var is_col_visible_strict = wrapped_x >= -1000.0 and wrapped_x < (total_width + 1000.0)
		if wrapped_x >= (screen_width + col_width * 3.0): is_col_visible_strict = false
		if wrapped_x <= -(col_width * 4.0): is_col_visible_strict = false
		
		# Logic removed: redundant loop replaced by secondary loop below
		var col_icons = col_wrappers[i].get_children()
		if col_icons.is_empty(): continue

		if not is_col_visible_strict:
			for icon in col_icons: icon.visible = false
			continue 
			
		# Logic removed: redundant loop replaced by secondary loop below
		# with the existing `icons_by_zone` and `get_item_height` structure.
		# I will retain the original Y calculation logic but ensure `is_col_visible`
		# is respected.
		
	# 1. Calculate Total Content Height & Cache Y Positions
		var content_height = 0.0
		var item_y_positions = [] # Store base Y for each item
		
		for icon in col_icons:
			item_y_positions.append(content_height)
			content_height += get_item_height(icon)
			
		var loop_height = max(content_height, screen_height + 400.0)
		
		# INTERACTIVE ZOOM & AUTO-SCROLL (Pinned App Column)
		var zoom_scale = 1.0
		if i == pinned_col_index:
			# Only zoom if we are actively dragging/touching THIS column
			if is_dragging and transform_col_touch_index == i:
				var target_zoom = 1.0
				
				# AUTO-SCROLL CHECK
				# If holding without moving for > System Long Press + 500ms
				if not is_horiz_dragging and not is_vert_dragging:
					pinned_touch_timer += delta
					# User requested Long Press + 1000ms (was 500ms)
					var threshold = Settings.system_long_press_time + 1.0
					
					if pinned_touch_timer > threshold:
						target_zoom = 1.1 # Only Zoom when Scrolling starts
						col_offsets[i] += 600.0 * delta # Auto-scroll UP (Reverse) + Faster (600)
						emit_signal("request_close_ctx_menu") # Close any open context menu immediately
				else:
					pinned_touch_timer = 0.0
					
				pinned_zoom_strength = lerp(pinned_zoom_strength, target_zoom, delta * 10.0) 
			else:
				pinned_zoom_strength = lerp(pinned_zoom_strength, 1.0, delta * 10.0)
				pinned_touch_timer = 0.0
			
			zoom_scale = pinned_zoom_strength # V14.46: Apply the lerped value
		for r in range(col_icons.size()):
			var icon = col_icons[r]
			if icon.get("is_dragging_item"): continue # Skip if actively being dragged
			
			var start_y_in_col = item_y_positions[r]
			
			# V14.51: Apply dynamic "Gap" shifting if this is the preview column
			if preview_target.get("column", -1) == i:
				var target_idx = preview_target.get("index", 0)
				if r >= target_idx:
					start_y_in_col += ICON_SPACING * preview_shift_weights[i]
			
			var base_y = effective_top_padding + start_y_in_col + col_offsets[i]
			var wrapped_y = base_y # No wrapping in loop mode for minimal
			if not (is_home_zm and Settings.current_config.get("minimal_mode", false)):
				# Allow wrapping with a large negative buffer so they can scroll off top
				wrapped_y = fposmod(base_y + 400, loop_height) - 400
			
			# Temporarily disabled hiding/fading at bounds - HUGE range
			if wrapped_y > -2000 and wrapped_y < screen_height + 2000:
				icon.visible = true
				# CENTER the item in its slot
				var half_height = get_item_height(icon) * 0.5
				var visual_center_y = wrapped_y + half_height
				
				# SPACING ZOOM: Spread items out from ACTION CENTER (Touch Position)
				# This ensures the item under the finger stays under the finger.
				if zoom_scale > 1.01:
					var anchor_y = screen_height * 0.5 # Default to center
					
					# If we are actively interacting with this column, assume the finger is the anchor
					if is_dragging and transform_col_touch_index == i:
						anchor_y = last_drag_pos.y
					
					var dist_from_anchor = visual_center_y - anchor_y
					# Scale the distance (effectively spacing out items relative to finger)
					visual_center_y = anchor_y + (dist_from_anchor * zoom_scale)
				
				var pos = Vector2(wrapped_x + (col_width * 0.5), visual_center_y)
				
				if icon is Control:
					icon.position = pos - (icon.size * 0.5)
					icon.scale = Vector2(zoom_scale, zoom_scale)
					icon.pivot_offset = icon.size * 0.5
				else:
					icon.position = pos
					icon.scale = Vector2(zoom_scale, zoom_scale)
				
				# Temporarily disabled fading
				icon.modulate.a = 1.0
				
			else:
				icon.visible = false

func get_item_height(node: CanvasItem) -> float:
	if node.has_method("get_custom_height"):
		return node.get_custom_height()
	return ICON_SPACING


func _is_launcher_item(node: Node) -> bool:
	var curr = node
	while curr:
		if curr.has_meta("launcher_item"): return true
		if curr == self: return true
		curr = curr.get_parent()
	return false

func get_drop_target(pos: Vector2) -> Dictionary:
	var local_pos = to_local(pos)
	var col_width = screen_width / 4.0
	
	# 1. Determine Column via Boundaries
	var col_idx = -1
	for i in range(column_count): 
		var col_start_x = (i * col_width) + h_offset
		if local_pos.x >= col_start_x and local_pos.x < col_start_x + col_width:
			col_idx = i
			break
			
	if col_idx == -1: 
		# Fallback: Nearest Column (for drops slightly outside bounds)
		var min_dist = 99999.0
		for i in range(column_count):
			var center_x = (i * col_width) + h_offset + (col_width * 0.5)
			var dist = abs(local_pos.x - center_x)
			if dist < min_dist:
				min_dist = dist
				col_idx = i
	
	if col_idx == -1: return {}
	
	# 2. Determine Vertical Index
	var effective_top = TOP_PADDING
	if is_home_zm and Settings.current_config.get("minimal_mode", false):
		effective_top = screen_height - 800.0
	
	var local_y = local_pos.y - effective_top - col_offsets[col_idx]
	
	# Account for wrap-around fposmod logic in _process if not minimal mode
	if not (is_home_zm and Settings.current_config.get("minimal_mode", false)):
		var content_height = 0.0
		var col_icons = col_wrappers[col_idx].get_children()
		for icon in col_icons:
			content_height += get_item_height(icon)
		
		# V14.47: Use the same loop_height logic as _process
		var loop_height = max(content_height, screen_height + 400.0)
		local_y = fposmod(local_y + 400, loop_height) - 400
		
	# Find slot by iterating items (more accurate for variable heights)
	# V14.52: IGNORE the dragging icon during slot calculation
	var current_y = 0.0
	var item_idx = 0
	var all_col_icons = col_wrappers[col_idx].get_children()
	var static_icons = []
	for icon in all_col_icons:
		if not icon.get("is_dragging_item", false):
			static_icons.append(icon)
			
	for icon in static_icons:
		var h = get_item_height(icon)
		if local_y < current_y + (h * 0.5):
			break
		current_y += h
		item_idx += 1
	
	print("ZM: get_drop_target (", pos, ") -> Col: ", col_idx, " Row: ", item_idx)
	return {"column": col_idx, "index": item_idx}

func show_drop_preview(pos: Vector2):
	preview_target = get_drop_target(pos)

func clear_drop_preview():
	preview_target = {}

func get_state() -> Dictionary:
	return {
		"h_offset": h_offset,
		"col_offsets": col_offsets.duplicate()
	}

func restore_state(state: Dictionary):
	if state.has("h_offset"):
		h_offset = state["h_offset"]
		target_h_offset = h_offset # Sync target
	
	if state.has("col_offsets"):
		var saved_cols = state["col_offsets"]
		for i in range(min(col_offsets.size(), saved_cols.size())):
			col_offsets[i] = saved_cols[i]
	
	wake_up()
