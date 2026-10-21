class_name CityMapSigns
extends CityMapConstants

@warning_ignore_start("integer_division")

const ENAMEL_FONT_HEIGHTS := [7, 9, 11]

var map: CityMapControl
var _sign_font: SystemFont
var artwork_density := 1
var atlas := CitySignAtlas.new()
var sign_entries: Array[CityMapSigns.Entry] = []
var sign_entries_city: CityState
var sign_entries_zoom := -1.0
var _sign_layout_signature: Array = []
var external_sign_layout_token: Array = []
var sign_cache_build_count := 0


func _init(control: CityMapControl) -> void:
	map = control


func set_animated_palette(texture: Texture2D) -> void:
	map.animated_palette_texture = texture
	map.layers._sync_base_material()


func set_dark_underground_palette(texture: Texture2D) -> void:
	map.dark_underground_palette_texture = texture
	map.layers._sync_base_material()


func set_signs_visible(value: bool) -> void:
	if map.signs_visible == value:
		return

	map.signs_visible = value
	map.queue_redraw()


func sign_source_entries() -> Array[CityMapSigns.Entry]:
	if not map.signs_visible or map.city == null:
		return []

	_ensure_sign_entries()

	return sign_entries.duplicate()


func _ensure_sign_entries() -> void:
	var map_edge: int = map.city.map_size if map.city != null else 128

	if sign_entries_city == map.city and is_equal_approx(sign_entries_zoom, map.zoom_factor):
		return

	if map.city == null:
		sign_entries.clear()
		sign_entries_city = null

		return

	var sign_texts := map.city.sign_texts()

	# the original paints a sign at each connection marker; no record holds it
	sign_texts.merge(CityNeighbors.connection_sign_texts(map.city))
	var sign_indices := PackedInt32Array(sign_texts.keys())
	sign_indices.sort()
	var sign_values := []

	# a layout reads only the sign tiles, so their values replace a map hash
	for index in sign_indices:
		sign_values.append(index)
		sign_values.append(sign_texts[index])

		if index < map.city.altitude_words.size():
			sign_values.append(map.city.altitude_words[index])
			sign_values.append(map.city.terrain[index])
			sign_values.append(map.city.tile_flags[index])

	var signature := [
		map_edge,
		map.city.visible_altitude_levels,
		map.city.compass_rotation(),
		hash(sign_values),
	]

	if _sign_layout_signature == signature and is_equal_approx(sign_entries_zoom, map.zoom_factor):
		sign_entries_city = map.city

		return

	_sign_layout_signature = signature
	sign_entries.clear()
	sign_entries_city = map.city
	sign_entries_zoom = map.zoom_factor
	sign_cache_build_count += 1
	var view_index := sign_view_index(map.zoom_factor)
	var configuration := Renderer.view_configuration(view_index)
	var divisor := configuration.divisor
	# each tile routine passes the bottom of the ground sprite, and the sign
	# painter FUN_0044d9a0 moves up half a tile: the center of the tile
	var anchor_drop := Vector2(0, (configuration.tile_height - configuration.half_height) * divisor)
	var font := _get_sign_font()
	var font_size := _em_size(font, ENAMEL_FONT_HEIGHTS[view_index])
	var positions: Array[Vector2i] = []

	for index in sign_indices:
		var x := index / map_edge
		var y := index % map_edge
		positions.append(Vector2i((x + y) * map_edge + y, index))

	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x)

	for entry in positions:
		var x := entry.y / map_edge
		var y := entry.y % map_edge

		if not map.city.tile_is_visible(x, y):
			continue

		var label_text: String = sign_texts.get(entry.y, "")

		if label_text.is_empty():
			continue

		var polygon := Renderer.tile_polygon(map.city, x, y)

		if polygon.size() != 4:
			continue

		var native_width := ceilf(font.get_string_size(
			label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(font_size)
		).x)
		var anchor := polygon[0] + anchor_drop
		var source_multiplier := maxf(1.0, 1.0 / map.zoom_factor)
		var layout := sign_layout(
			anchor, native_width * source_multiplier,
			view_index, source_multiplier,
		)
		var bounds := layout.bounds(source_multiplier)
		var sign_entry := Entry.new()
		sign_entry.key = map.city.index_of(x, y)
		sign_entry.anchor = anchor
		sign_entry.label = label_text
		sign_entry.text_width = native_width
		sign_entry.bounds = Rect2i(
			Vector2i(floori(bounds.position.x), floori(bounds.position.y)),
			Vector2i(ceili(bounds.size.x), ceili(bounds.size.y)),
		)
		sign_entry.draw_order = (x + y) * map_edge + y
		sign_entries.append(sign_entry)


func _invalidate_sign_entries() -> void:
	external_sign_layout_token.clear()
	_sign_layout_signature.clear()
	sign_entries.clear()
	sign_entries_city = null
	sign_entries_zoom = -1.0


func _draw_signs(scale: float, offset: Vector2) -> void:
	var map_edge: int = map.city.map_size if map.city != null else 128

	if not map.signs_visible or map.city == null or map.city_source.size.x <= map_edge:
		return

	_ensure_sign_entries()
	var view_index := sign_view_index(map.zoom_factor)
	var display_multiplier := sign_display_multiplier(map.zoom_factor) * map.map_pixel_ratio
	if AppUiTheme.selected == "classic_dos":
		for entry in sign_entries:
			_draw_dos_sign(entry, (offset + entry.anchor * scale).round(), display_multiplier)
		return
	atlas.prepare(map, sign_entries, view_index, artwork_density, _get_sign_font())
	for entry in sign_entries:
		if not Rect2(entry.bounds).intersects(map.camera.visible_source_rect()):
			continue
		var slot: CitySignAtlas.Slot = atlas.slots.get(entry.label)
		if slot == null:
			continue
		var origin := (offset + entry.anchor * scale).round()
		map.draw_texture_rect_region(atlas.pages[slot.page].get_texture(),
			Rect2(origin + slot.bounds.position * display_multiplier,
				Vector2(slot.region.size) / artwork_density * display_multiplier), slot.region)
		draw_text(map, entry, slot, origin, display_multiplier, view_index)


func draw_text(canvas: CanvasItem, entry: Entry, slot: CitySignAtlas.Slot, origin: Vector2, multiplier: float, view: int) -> void:
	var font := _get_sign_font()
	var native_size := maxi(1, roundi(_em_size(font, ENAMEL_FONT_HEIGHTS[view])))
	# Rasterize at twice the physical display density, then fit to the same board.
	var raster_scale := maxf(1.0, canvas.get_global_transform_with_canvas().get_scale().y) * 2.0
	var screen_size := maxi(1, roundi(native_size * multiplier * raster_scale))
	if entry.screen_font_size != screen_size:
		entry.screen_font_size = screen_size
		entry.screen_text_width = font.get_string_size(entry.label, HORIZONTAL_ALIGNMENT_LEFT, -1, screen_size).x
	# Font hinting can change the advance at another size. Fit that advance
	# to the board without changing its world-space position or bounds.
	var fit := slot.text_width * multiplier / maxf(1.0, entry.screen_text_width)
	var text_origin := origin + (slot.face * Vector2(5, 3)) * multiplier
	canvas.draw_set_transform_matrix(Transform2D(Vector2(fit, fit * 0.5), Vector2(0, 1.0 / raster_scale), text_origin))
	canvas.draw_string(font, Vector2(0, font.get_ascent(screen_size)), entry.label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, screen_size, Color("eee9d3"))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


func set_high_resolution(enabled: bool) -> void:
	var density := 2 if enabled else 1
	if artwork_density == density:
		return
	artwork_density = density
	_sign_font = null
	map.queue_redraw()


static func sign_view_index(zoom: float) -> int:
	if zoom <= 0.25:
		return Renderer.VIEW_SMALL

	if zoom <= 0.5:
		return Renderer.VIEW_MEDIUM

	return Renderer.VIEW_LARGE


static func sign_display_multiplier(zoom: float) -> float:
	return maxf(1.0, zoom)


static func sign_layout(
	anchor: Vector2, text_width: float, view_index: int, display_multiplier := 1.0
) -> Layout:
	if view_index < Renderer.VIEW_SMALL or view_index > Renderer.VIEW_LARGE:
		return null

	var multiplier := maxf(1.0, display_multiplier)
	var width := ceilf(text_width) + 10.0 * multiplier
	var height: float = (ENAMEL_FONT_HEIGHTS[view_index] + 6.0) * multiplier
	var post_height := maxf([12.0, 17.0, 24.0][view_index] * multiplier, width * 0.25 + 4.0 * multiplier)
	var top := anchor + Vector2(-width * 0.5, -post_height - height - width * 0.25)
	var layout := Layout.new()
	layout.face = Transform2D(Vector2(1, 0.5), Vector2(0, 1), top)
	layout.face_size = Vector2(width, height)
	layout.panel = Rect2(top + Vector2(0, -multiplier), Vector2(width + 2 * multiplier, height + width * 0.5 + multiplier))
	layout.post = Rect2(anchor + Vector2(-multiplier, -post_height), Vector2(2 * multiplier, post_height))
	return layout


# the executable asks for a character cell of `cell_height` pixels, ascent
# and descent together. A Godot font size is the em size, which is smaller
static func _em_size(font: Font, cell_height: float) -> float:
	const REFERENCE_SIZE := 100

	return cell_height * REFERENCE_SIZE / font.get_height(REFERENCE_SIZE)


func _get_sign_font() -> Font:
	if _sign_font == null:
		_sign_font = SystemFont.new()
		_sign_font.font_names = PackedStringArray(["Arial"])
		_sign_font.font_weight = 600
		_sign_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_sign_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_sign_font.oversampling = 1.0

	return _sign_font


class Entry extends RefCounted:
	var key: int
	var anchor: Vector2
	var label: String
	var text_width: float
	var bounds: Rect2i
	var draw_order: int
	var screen_font_size := 0
	var screen_text_width := 0.0


class Layout extends RefCounted:
	var panel: Rect2
	var post: Rect2
	var face: Transform2D
	var face_size: Vector2


	func bounds(padding := 1.0) -> Rect2:
		var rect := panel.merge(post).grow(padding)
		var start := rect.position.floor()
		return Rect2(start, rect.end.ceil() - start)


func _draw_dos_sign(entry: Entry, origin: Vector2, multiplier: float) -> void:
	var font := AppUiTheme.current().default_font
	var font_size := maxi(7, roundi(11 * multiplier))
	var width := ceilf(font.get_string_size(entry.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var height := ceilf(font.get_height(font_size))
	var panel := Rect2(origin + Vector2(-width * 0.5 - 3, -height - 28 * multiplier), Vector2(width + 6, height + 4))
	panel.position = panel.position.round()
	if not panel.expand(origin).intersects(Rect2(Vector2.ZERO, map.size)):
		return
	map.draw_line(origin, Vector2(origin.x, panel.end.y), Color("808080"), maxf(1, multiplier))
	map.draw_rect(panel, Color("c0c0c0"))
	map.draw_line(panel.position, Vector2(panel.end.x, panel.position.y), Color.WHITE)
	map.draw_line(panel.position, Vector2(panel.position.x, panel.end.y), Color.WHITE)
	map.draw_line(Vector2(panel.position.x, panel.end.y), panel.end, Color("404040"))
	map.draw_line(Vector2(panel.end.x, panel.position.y), panel.end, Color("404040"))
	map.draw_string(font, panel.position + Vector2(3, 2 + font.get_ascent(font_size)), entry.label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
