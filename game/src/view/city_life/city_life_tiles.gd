class_name CityLifeTiles
extends RefCounted
## Retain projected road centers and update only edited cells. Sorting remains
## identical to the original x/y scan, preserving decorative spawn RNG order.
@warning_ignore_start("integer_division")

var geometry := CityLifeGeometry.new()
var points: Dictionary[int, Vector2i] = {}
var tiles: Array[Vector2i] = []
var viewport := Rect2i()
var search := Rect2i()
var collecting := false
var _indices := PackedInt32Array()
var _cursor := 0


func collect(city: CityState, bounds: Rect2i, budget_usec := 0) -> Array[Vector2i]:
	geometry.sync(city)
	var rebuild := geometry.reset or bounds != viewport
	if geometry.reset:
		points.clear()
	if rebuild:
		viewport = bounds
		search = search_bounds(city, bounds)
	# Changes are applied even outside the viewport: a later pan must not reuse
	# an old center for an edited bridge or ramp.
	var affected := false
	# Eligibility and the projected center read only this cell's geometry.
	# Lane connections and receivers still use the expanded neighbor set.
	for tile in geometry.edited:
		var index := city.index_of(tile.x, tile.y)
		if index < 0:
			continue
		var previous: Variant = points.get(index)
		points.erase(index)
		if search.has_point(tile):
			_update(city, tile, index)
			# Nearby building/zone changes also reach this cache. Re-sort the
			# complete road list only if its projected membership actually changed.
			affected = affected or previous != points.get(index)
	if rebuild:
		collecting = true
		_cursor = 0
		_indices = CityLifePaths.candidate_indices(city, search.position, search.end - Vector2i.ONE)
		for index in points.keys():
			if not search.has_point(Vector2i(index / city.map_size, index % city.map_size)):
				points.erase(index)
	var completed := false
	if collecting:
		var deadline := Time.get_ticks_usec() + budget_usec
		while _cursor < _indices.size():
			var index := _indices[_cursor]
			_cursor += 1
			if not points.has(index):
				_update(city, Vector2i(index / city.map_size, index % city.map_size), index)
			if budget_usec > 0 and Time.get_ticks_usec() >= deadline:
				return []
		collecting = false
		_indices.clear()
		completed = true
	if completed or affected:
		tiles.clear()
		var indices := points.keys()
		indices.sort()
		for index in indices:
			if viewport.has_point(points[index]):
				tiles.append(Vector2i(index / city.map_size, index % city.map_size))
	return tiles


func _update(city: CityState, tile: Vector2i, index: int) -> void:
	if CityLifePaths.ports(city, tile) > 0 and city.land_altitude(tile.x, tile.y) < city.visible_altitude_levels:
		points[index] = Vector2i(CityLifePaths.point(city, tile, 0, 2, 0.5, false))


static func search_bounds(city: CityState, bounds: Rect2i) -> Rect2i:
	var first := Vector2i(city.map_size, city.map_size)
	var last := Vector2i.ZERO
	for corner in [bounds.position, bounds.position + Vector2i(bounds.size.x, 0),
		bounds.end, bounds.position + Vector2i(0, bounds.size.y)]:
		for altitude in [0, 31]:
			var difference: float = (corner.x - 32 - city.map_size * 16 - 16) / 16.0
			var total: float = (corner.y - 512 - 8 + altitude * 12) / 8.0
			var point := Vector2i(floori((total + difference) * 0.5), floori((total - difference) * 0.5))
			first = first.min(point - Vector2i(2, 2))
			last = last.max(point + Vector2i(2, 2))
	first = first.max(Vector2i.ZERO)
	last = last.min(Vector2i(city.map_size - 1, city.map_size - 1))
	return Rect2i(first, (last - first + Vector2i.ONE).max(Vector2i.ZERO))
