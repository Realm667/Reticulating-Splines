class_name CityNightTemplates
extends RefCounted
## Reusable road light rasters. Keys contain local geometry and light profiles;
## foreground silhouettes are applied separately at each world position.

const LIMIT := 256
const PAGE_EDGE := 512
var receivers: Dictionary[Array, Array] = {}
var textures: Dictionary[Array, Texture2D] = {}
var fixture_cache: Dictionary[Array, Dictionary] = {}
var _page: Image
var _page_texture: ImageTexture
var _page_cursor := Vector2i.ZERO
var _row_height := 0
var defer_updates := false
var _page_dirty := false


func clear() -> void:
	receivers.clear()
	textures.clear()
	fixture_cache.clear()
	_page = null
	_page_texture = null
	_page_cursor = Vector2i.ZERO
	_row_height = 0
	_page_dirty = false
	defer_updates = false


func flush() -> void:
	if _page_dirty:
		_page_texture.update(_page)
		_page_dirty = false


func fixtures(app: CityApplication, tile: Vector2i, origin: Vector2i, layout: Array[Dictionary],
		masker: CityLifeCanvas, raster_scale := 1) -> Dictionary:
	var city := app.document_state.city
	var key: Array = [raster_scale]
	var axes: Dictionary[int, int] = {}
	for fixture in layout:
		key.append([fixture.offset, fixture.get("center", Vector2.ZERO), fixture.enter,
			CityNightFixtures._foot(city, tile, fixture.offset, fixture.enter, raster_scale) - origin * raster_scale])
		if not axes.has(int(fixture.enter) % 2):
			axes[int(fixture.enter) % 2] = fixture.enter
	var directions := CityNightFixtures.signal_directions(city, tile)
	key.append(directions)
	for direction in directions:
		var forward := Vector2(CityLifePaths.DIRECTIONS[direction])
		var side := Vector2(-forward.y, forward.x)
		key.append(CityNightFixtures._foot(city, tile, forward * 0.36 + side * 0.30, direction, raster_scale) - origin * raster_scale)
		if not axes.has(direction % 2):
			axes[direction % 2] = direction
	# Compare exact mask pixels in local coordinates, not source revisions or
	# absolute placement. Cached output cannot leak through a different facade.
	for axis in axes:
		var masks: Array = [axis]
		for mask: Dictionary in masker._candidates(app, tile, axes[axis]):
			masks.append([mask.origin - origin, mask.image.get_size(), mask.image.get_format(), mask.image.get_data()])
		key.append(masks)
	var cached: Dictionary = fixture_cache.get(key, {})
	if cached.is_empty():
		var built := CityNightFixtures.build(app, tile, origin, layout, masker, texture, raster_scale)
		var relative_signals: Array[Dictionary] = []
		for signal_light: Dictionary in built.signals:
			relative_signals.append({"origin": signal_light.origin - Vector2(origin), "lenses": signal_light.lenses, "axis": signal_light.axis})
		cached = {"fixtures": built.fixtures, "signals": relative_signals}
		if fixture_cache.size() >= LIMIT:
			fixture_cache.erase(fixture_cache.keys()[0])
	else:
		fixture_cache.erase(key)
	fixture_cache[key] = cached
	var signals: Array[Dictionary] = []
	for signal_light: Dictionary in cached.signals:
		signals.append({"origin": signal_light.origin + Vector2(origin), "lenses": signal_light.lenses, "axis": signal_light.axis})
	return {"fixtures": cached.fixtures, "signals": signals}


func receiver(city: CityState, tile: Vector2i, origin: Vector2i, lights: Array[Dictionary], roads: CityLifeLights) -> Array:
	var height := CityLifePaths.edge_height(city, tile, 0)
	var key: Array = [CityLifePaths.ports(city, tile), CityLifePaths.diagonal(city, tile),
		CityLifeLights._project(city, tile, Vector2.ZERO, height) - Vector2(origin), roads.raster_scale]
	for enter in 4:
		key.append(CityLifePaths.edge_height(city, tile, enter) - height)
		for exit in 4:
			key.append(CityLifePaths.can_turn(city, tile, enter, exit))
	for light in lights:
		key.append([light.offset, light.get("enter", -1), light.color, light.radius, light.intensity])
	if receivers.has(key):
		var cached: Array = receivers[key]
		receivers.erase(key)
		receivers[key] = cached
		return cached
	var parts := _rasterize(city, tile, origin, lights, roads)
	if receivers.size() >= LIMIT:
		receivers.erase(receivers.keys()[0])
	receivers[key] = parts
	return parts


func texture(image: Image) -> Texture2D:
	# Identical masked output shares a GPU texture and can use renderer batching.
	# Compare complete bytes, not a hash alone. Visible entries retain references
	# even if an old interned texture leaves this bounded lookup table.
	var key: Array = [image.get_size(), image.get_format(), image.get_data()]
	if textures.has(key):
		var cached: Texture2D = textures[key]
		textures.erase(key)
		textures[key] = cached
		return cached
	var result := _atlas_texture(image)
	if textures.size() >= LIMIT:
		textures.erase(textures.keys()[0])
	textures[key] = result
	return result


func _atlas_texture(image: Image) -> Texture2D:
	# The dummy renderer has no draw batches and does not retain texture
	# updates for CPU readback. Keep its existing standalone image path.
	if DisplayServer.get_name() == "headless":
		return ImageTexture.create_from_image(image)
	var size := image.get_size()
	var padded := size + Vector2i(2, 2)
	if padded.x > PAGE_EDGE or padded.y > PAGE_EDGE or image.get_format() != Image.FORMAT_RGBA8:
		return ImageTexture.create_from_image(image)
	if _page != null and _page_cursor.x + padded.x > PAGE_EDGE:
		_page_cursor = Vector2i(0, _page_cursor.y + _row_height)
		_row_height = 0
	if _page == null or _page_cursor.y + padded.y > PAGE_EDGE:
		flush()
		_page = Image.create(PAGE_EDGE, PAGE_EDGE, false, Image.FORMAT_RGBA8)
		_page_texture = ImageTexture.create_from_image(_page)
		_page_cursor = Vector2i.ZERO
		_row_height = 0
	var origin := _page_cursor + Vector2i.ONE
	_page.blit_rect(image, Rect2i(Vector2i.ZERO, size), origin)
	# Replicate edge texels: linear ground filtering must behave exactly like
	# a clamped standalone texture, including beside unrelated atlas entries.
	_page.blit_rect(image, Rect2i(0, 0, size.x, 1), origin - Vector2i(0, 1))
	_page.blit_rect(image, Rect2i(0, size.y - 1, size.x, 1), origin + Vector2i(0, size.y))
	_page.blit_rect(image, Rect2i(0, 0, 1, size.y), origin - Vector2i(1, 0))
	_page.blit_rect(image, Rect2i(size.x - 1, 0, 1, size.y), origin + Vector2i(size.x, 0))
	for x in 2:
		for y in 2:
			var border := Vector2i(-1 if x == 0 else size.x, -1 if y == 0 else size.y)
			_page.set_pixelv(origin + border, image.get_pixel(x * (size.x - 1), y * (size.y - 1)))
	_page_dirty = true
	if not defer_updates:
		flush()
	var result := AtlasTexture.new()
	result.atlas = _page_texture
	result.region = Rect2(origin, size)
	result.filter_clip = true
	_page_cursor.x += padded.x
	_row_height = maxi(_row_height, padded.y)
	return result


static func _rasterize(city: CityState, tile: Vector2i, origin: Vector2i, lights: Array[Dictionary], roads: CityLifeLights) -> Array:
	var parts: Array = []
	var edge := 64 * roads.raster_scale
	origin *= roads.raster_scale
	for enter in 4:
		if not CityLifePaths.ports(city, tile) & (1 << enter):
			continue
		var lamps: Array[Dictionary] = []
		for light in lights:
			if light.has("enter") and int(light.enter) != enter and not CityLifePaths.can_turn(city, tile, enter, int(light.enter)):
				continue
			lamps.append({"position": light.position, "color": Color(str(light.color)), "radius": float(light.radius), "intensity": float(light.intensity)})
		var image := NativeVisualRaster.night_receiver(Vector2i(edge, edge), origin, roads._road_patches(city, tile, enter), lamps)
		parts.append({"enter": enter, "image": image})
	return parts
