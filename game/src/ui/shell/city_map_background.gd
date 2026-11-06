class_name CityMapBackground
extends Control
## Viewport backdrop below the live map and region previews.

var map: CityMapControl
var style := "classic":
	set(value):
		style = value
		queue_redraw()

var _fills: Dictionary[String, GradientTexture2D] = {}
var _grain: ImageTexture
var _shadow: ImageTexture


func _ready() -> void:
	theme_changed.connect(queue_redraw)
	resized.connect(queue_redraw)


func refresh_shadows() -> void:
	if style == "diorama":
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	match style:
		"graphite":
			draw_texture_rect(_fill("303d47", "192127"), rect, false)
		"drafting_table":
			draw_texture_rect(_fill("263944", "202e37"), rect, false)
			_draw_grid()
		"atlas":
			draw_texture_rect(_fill("665f52", "514c43"), rect, false)
			if _grain == null:
				_grain = _paper_grain()
			draw_texture_rect(_grain, rect, true)
		"diorama":
			draw_texture_rect(_fill("3b484f", "303b43"), rect, false)
			_draw_shadows()
		_:
			draw_rect(rect, get_theme_color("map_canvas", "AppPalette"))


func _fill(center: String, edge: String) -> GradientTexture2D:
	if not _fills.has(center):
		var gradient := Gradient.new()
		gradient.set_color(0, Color(center))
		gradient.set_color(1, Color(edge))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 256
		texture.height = 256
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.53, 0.49)
		texture.fill_to = Vector2(1.0, 1.0)
		_fills[center] = texture
	return _fills[center]


func _draw_grid() -> void:
	var lines := PackedVector2Array()
	var rise := size.x * 0.5
	for y in range(-ceili(rise / 38.0) * 38, ceili(size.y + rise), 38):
		lines.append(Vector2(0.0, y))
		lines.append(Vector2(size.x, y + rise))
		lines.append(Vector2(0.0, y))
		lines.append(Vector2(size.x, y - rise))
	draw_multiline(lines, Color(0.57, 0.73, 0.79, 0.09), 1.0, true)


func _draw_shadows() -> void:
	if map == null or map.city == null or map.city_source == null:
		return
	if _shadow == null:
		_shadow = _diamond_shadow()
	var scale := map.camera._view_scale()
	var offset := map.camera._draw_offset(scale)
	var half := Vector2(CityIsometricRenderer.HALF_WIDTH, CityIsometricRenderer.HALF_HEIGHT) * map.city.map_size
	var center := Vector2(CityIsometricRenderer.SIDE_MARGIN, CityIsometricRenderer.TOP_MARGIN) + half
	var shadow_size := half * scale * 2.32
	var shift := Vector2(0.025, 0.042) * half.x * scale
	var shadow_rect := Rect2(offset + center * scale + shift - shadow_size * 0.5, shadow_size)
	draw_texture_rect(_shadow, shadow_rect, false, Color(1.0, 1.0, 1.0, 0.64))
	if map.data_view_mode == CityViewMode.Mode.NONE and not map.region_backdrop.state.is_empty():
		for cell: Vector2i in map.region_backdrop.textures:
			var neighbor := Rect2(shadow_rect.position + map.region_backdrop.displacement(cell) * scale, shadow_size)
			draw_texture_rect(_shadow, neighbor, false, Color(1.0, 1.0, 1.0, 0.28))


static func _paper_grain() -> ImageTexture:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	var random := RandomNumberGenerator.new()
	random.seed = 1729
	for y in image.get_height():
		for x in image.get_width():
			var light := 1.0 if random.randf() < 0.5 else 0.0
			image.set_pixel(x, y, Color(light, light, light, random.randf_range(0.0, 0.026)))
	return ImageTexture.create_from_image(image)


static func _diamond_shadow() -> ImageTexture:
	var image := Image.create_empty(128, 64, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var uv := (Vector2(x + 0.5, y + 0.5) / Vector2(image.get_size()) * 2.0 - Vector2.ONE).abs()
			var alpha := 1.0 - smoothstep(0.62, 0.99, uv.x + uv.y)
			image.set_pixel(x, y, Color(0.01, 0.035, 0.05, alpha))
	return ImageTexture.create_from_image(image)
