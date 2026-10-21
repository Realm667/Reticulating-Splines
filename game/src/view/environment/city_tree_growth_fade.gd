class_name CityTreeGrowthFade
extends CanvasGroup
## A short-lived copy of changed static regions, composited over their replacement.
## Includes terrain and shadows so overlapping trees blend as a finished image.
## No city writes, random state, per-frame rasterization or retained city snapshots.

@warning_ignore_start("integer_division")

const DURATION := 0.85
const PENDING_SECONDS := 10.0
const MAX_REGIONS := 64
const MAX_BYTES := 32 * 1024 * 1024
const SHADER := preload("res://src/view/environment/tree_growth_fade.gdshader")

signal settled

var pending: Dictionary = {}
var active: Dictionary = {}
var retained_bytes := 0
var _context: Array = []
var _edge := 1
var _clock := 0.0
var _times: Image
var _texture: ImageTexture


func _init() -> void:
	fit_margin = 0.0
	clear_margin = 0.0
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	shader_material.set_shader_parameter("duration", DURATION)
	material = shader_material
	hide()


func reset() -> void:
	var had_images := not active.is_empty()
	for key: Vector2i in active.keys():
		_remove(key)
	pending.clear()
	_context.clear()
	_clock = 0.0
	_times = null
	_texture = null
	material.set_shader_parameter("starts", null)
	hide()
	if had_images:
		settled.emit()


func discard_other_city(document_id: int) -> void:
	if not _context.is_empty() and _context[0] != document_id:
		reset()


# Compares the displayed city with a new snapshot. Only calendar-driven
# density increases/spread qualify; edits, loading and first views do not fade.
func observe(city: CityState, before: CityState, source: CityMapSource,
		context: Array, edge: int, enabled: bool) -> void:
	if not enabled or city == null or source == null:
		reset()
		return
	if _context != context or _edge != edge:
		reset()
		_context = context.duplicate(true)
		_edge = edge
		_times = Image.create(ceili(float(source.size.x) / edge), ceili(float(source.size.y) / edge), false, Image.FORMAT_RF)
		_texture = ImageTexture.create_from_image(_times)
		material.set_shader_parameter("starts", _texture)
		material.set_shader_parameter("extent", Vector2(_times.get_size() * edge))
		return
	if before == null or before.map_size != city.map_size or not ForestGrowth.due(city, before.age_in_days(), true):
		return
	var regions := {}
	for entry in source.meshes:
		regions[Vector2i(entry.position) / edge] = true
	for entry in source.tiles:
		regions[Vector2i(entry.position) / edge] = true
	if regions.is_empty() or city.buildings == before.buildings:
		return
	for index in city.buildings.size():
		var old := int(before.buildings[index])
		var now := int(city.buildings[index])
		if not grows(old, now):
			continue
		var tile := Vector2i(index / city.map_size, index % city.map_size)
		# Large-view coordinates are shared by every zoom. Include adjacent tree
		# layouts and their projected shadows when density changes a shared edge.
		var origin := IsometricGeometry.building_sprite_position(city, tile,
			city.object_altitude(tile.x, tile.y), Vector2i(64, 72))
		var bounds := Rect2i(origin - Vector2i(96, 96), Vector2i(256, 256))
		for x in range(maxi(0, bounds.position.x / edge), mini(_times.get_width(), bounds.end.x / edge + 1)):
			for y in range(maxi(0, bounds.position.y / edge), mini(_times.get_height(), bounds.end.y / edge + 1)):
				var key := Vector2i(x, y)
				if regions.has(key):
					pending[key] = _clock + PENDING_SECONDS


static func grows(before: int, after: int) -> bool:
	return (after >= BuildingTileIds.TREE_FIRST and after <= BuildingTileIds.TREE_LAST
		and (before == 0 or (before >= BuildingTileIds.TREE_FIRST and before < after)))


func capture(before: CityMapSource, after: CityMapSource, layers: CityMapLayers) -> void:
	if before == null or after == null or (pending.is_empty() and active.is_empty()):
		return
	var old := {}
	for entry in before.meshes:
		old[Vector2i(entry.position) / _edge] = entry
	for entry in before.tiles:
		old[Vector2i(entry.position) / _edge] = entry
	var present := {}
	var entries: Array = []
	entries.append_array(after.meshes)
	entries.append_array(after.tiles)
	for entry in entries:
		var key := Vector2i(entry.position) / _edge
		present[key] = true
		var previous: Variant = old.get(key)
		if previous == null or (entry is CityMapSource.MeshEntry and previous is CityMapSource.MeshEntry and entry.mesh == previous.mesh
				or entry is CityMapSource.TileEntry and previous is CityMapSource.TileEntry and entry.texture == previous.texture):
			continue
		if not pending.has(key):
			_remove(key) # A later edit must never be covered by an old forest.
			continue
		pending.erase(key)
		if active.has(key):
			continue # Successive growth converges to the latest image without a chain.
		var bytes := _bytes(previous)
		if active.size() >= MAX_REGIONS or retained_bytes + bytes > MAX_BYTES:
			continue
		var node: CanvasItem
		if previous is CityMapSource.MeshEntry:
			var mesh := MeshInstance2D.new()
			mesh.mesh = previous.mesh
			mesh.texture = previous.texture
			mesh.position = previous.position
			mesh.scale = Vector2.ONE * previous.divisor
			mesh.material = layers.visual_material(previous.emission, previous.seasons, previous.texture_pages)
			node = mesh
		else:
			var tile := TextureRect.new()
			tile.texture = previous.texture
			tile.position = previous.position
			tile.size = previous.size
			tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.self_modulate = previous.draw_color
			tile.material = layers.visual_material(previous.emission, previous.seasons)
			node = tile
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(node)
		active[key] = {"node": node, "start": _clock, "bytes": bytes}
		retained_bytes += bytes
		_times.set_pixelv(key, Color(_clock + 1.0, 0, 0))
	for key: Vector2i in active.keys():
		if not present.has(key):
			_remove(key)
	_upload()
	visible = not active.is_empty()


static func _bytes(entry: Variant) -> int:
	if entry is CityMapSource.MeshEntry:
		var total := 0
		for surface in entry.mesh.get_surface_count():
			total += entry.mesh.surface_get_array_len(surface) * 40 + entry.mesh.surface_get_array_index_len(surface) * 4
		return total
	return int(entry.texture.get_width()) * int(entry.texture.get_height()) * 4


func advance(delta: float) -> void:
	_clock += maxf(0.0, delta)
	var changed := false
	for key: Vector2i in active.keys():
		if _clock - float(active[key].start) >= DURATION:
			_remove(key)
			changed = true
	for key: Vector2i in pending.keys():
		if _clock >= float(pending[key]):
			pending.erase(key)
	if changed:
		_upload()
		if active.is_empty():
			settled.emit()
	visible = not active.is_empty()
	if visible:
		material.set_shader_parameter("clock", _clock + 1.0)
		var transform := get_global_transform_with_canvas().affine_inverse()
		material.set_shader_parameter("screen_to_source", Basis(Vector3(transform.x.x, transform.x.y, 0),
			Vector3(transform.y.x, transform.y.y, 0), Vector3(transform.origin.x, transform.origin.y, 1)))


func _remove(key: Vector2i) -> void:
	if not active.has(key):
		return
	var node: CanvasItem = active[key].node
	remove_child(node)
	node.queue_free()
	retained_bytes -= int(active[key].bytes)
	active.erase(key)
	if _times != null:
		_times.set_pixelv(key, Color(0, 0, 0))


func _upload() -> void:
	if _texture != null:
		_texture.update(_times)
