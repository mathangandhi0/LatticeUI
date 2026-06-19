extends Node

# Standard Android Adaptive Icon Size: 108dp (we use px)
# We will generate large masks (e.g. 512x512) for quality
const MASK_SIZE = 512
const CENTER = Vector2(MASK_SIZE/2.0, MASK_SIZE/2.0)
const RADIUS = MASK_SIZE / 2.0

func generate_masks(output_dir: String = "user://masks/"):
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("masks"):
		dir.make_dir("masks")
		print("MaskGenerator: Created 'masks' directory.")
	
	save_mask("circle", draw_circle_shape(), output_dir)
	save_mask("squircle", draw_squircle_shape(), output_dir)
	save_mask("rounded square", draw_rounded_square_shape(), output_dir)
	save_mask("teardrop", draw_teardrop_shape(), output_dir)
	save_mask("message", draw_message_shape(), output_dir)
	save_mask("square", draw_square_shape(), output_dir)
	print("MaskGenerator: All masks generated.")

func save_mask(name: String, image: Image, path: String):
	var full_path = path + name + ".png"
	image.save_png(full_path)
	print("MaskGenerator: Saved " + full_path)

func create_image_from_viewport(draw_func: Callable) -> Image:
	var img = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8)
	
	# Since we can't easily capture a viewport without adding to tree and waiting a frame,
	# we will implement the drawing manually using Image set_pixel or specialized drawing algorithms?
	# NO, that's slow and complex for anti-aliasing.
	# BETTER: Use a SubViewport container in the scene?
	# OR just use Geometry/SDF math in GDScript to set pixels?
	# The BEST way to get high-quality AA masks without a Viewport is SDF math per pixel.
	# It's fast enough for a 512x512 image done once.
	
	for y in range(MASK_SIZE):
		for x in range(MASK_SIZE):
			var uv = Vector2(x, y) / float(MASK_SIZE)
			var d = draw_func.call(uv)
			# AA: Smoothstep around 0
			var alpha = 1.0 - smoothstep(-0.002, 0.002, d) # 0.002 is ~1px at 512
			if alpha > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, alpha))
	
	return img

# SDF Functions adapted from Shader
# Returns distance (negative inside, positive outside)

# Circle
func draw_circle_shape() -> Image:
	return create_image_from_viewport(func(uv):
		return uv.distance_to(Vector2(0.5, 0.5)) - 0.5
	)

# Squircle (Superellipse)
func draw_squircle_shape() -> Image:
	return create_image_from_viewport(func(uv):
		var p = (uv - Vector2(0.5, 0.5)) * 2.0
		return pow(pow(abs(p.x), 4.0) + pow(abs(p.y), 4.0), 1.0/4.0) - 1.0
	)

# Rounded Square
func draw_rounded_square_shape() -> Image:
	return create_image_from_viewport(func(uv):
		return sd_rounded_box(uv - Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector4(0.15, 0.15, 0.15, 0.15))
	)

# Teardrop (Bottom Left Sharp)
func draw_teardrop_shape() -> Image:
	return create_image_from_viewport(func(uv):
		# TL, TR, BR, BL
		# BL is Sharp (0.0)
		return sd_rounded_box(uv - Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector4(0.5, 0.5, 0.5, 0.0))
	)

# Message (Bottom Right Sharp)
func draw_message_shape() -> Image:
	return create_image_from_viewport(func(uv):
		# TL, TR, BR, BL
		return sd_rounded_box(uv - Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector4(0.5, 0.5, 0.0, 0.5))
	)

# Square
func draw_square_shape() -> Image:
	return create_image_from_viewport(func(uv):
		var d = abs(uv - Vector2(0.5, 0.5)) - Vector2(0.5, 0.5)
		return max(d.x, d.y)
	)

# Helper: SDF Rounded Box with varying radii
# r = vec4(TopLeft, TopRight, BottomRight, BottomLeft)
func sd_rounded_box(p: Vector2, b: Vector2, r: Vector4) -> float:
	# Select radius based on quadrant
	var rad_x = 0.0
	
	if p.x > 0.0: # Right
		if p.y > 0.0: rad_x = r.z # BR
		else: rad_x = r.y # TR
	else: # Left
		if p.y > 0.0: rad_x = r.w # BL
		else: rad_x = r.x # TL
	
	var q = abs(p) - b + Vector2(rad_x, rad_x)
	return min(max(q.x, q.y), 0.0) + Vector2(max(q.x, 0.0), max(q.y, 0.0)).length() - rad_x
