class_name CityLifeLights
extends RefCounted
## Cosmetic emission and road-only light. All city geometry is read-only.
@warning_ignore_start("integer_division")

const HEADLIGHT := Color("ffe3a0")
const TAILLIGHT := Color("ff3426")
const FORWARD := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const REACH := 22.0
const SURFACE_LIMIT := 1024
var masks: Dictionary[String, Image] = {}
var roads: Dictionary[Vector3i, Array] = {}
var surfaces: Dictionary[Vector4i, Dictionary] = {}
var visible_roads: Dictionary[Vector3i, Array] = {}
var prepared_receivers := 0
var geometry_reset := false
var vehicle_planes: Dictionary[Vector4i, Vector4] = {}
var sprite_shears: Dictionary[Vector4i, float] = {}
var _geometry := CityLifeGeometry.new()
var raster_scale := 1


func set_raster_scale(value: int) -> void:
	if raster_scale == value:
		return
	raster_scale = value
	roads.clear()
	clear_surfaces()


# Global revisions decide when to compare. Only changed road geometry and its
# immediate connections invalidate receivers; distant development keeps them.
func sync_geometry(city: CityState) -> Dictionary[Vector2i, bool]:
	var changed := _geometry.sync(city)
	geometry_reset = _geometry.reset
	if geometry_reset:
		roads.clear()
		vehicle_planes.clear()
		sprite_shears.clear()
		clear_surfaces()
		return changed
	if changed.is_empty():
		return changed
	for key in vehicle_planes.keys():
		if changed.has(Vector2i(key.x, key.y)):
			vehicle_planes.erase(key)
	for key in sprite_shears.keys():
		if changed.has(Vector2i(key.x, key.y)):
			sprite_shears.erase(key)
	for tile in changed:
		for axis in 4:
			var key := Vector3i(tile.x, tile.y, axis)
			roads.erase(key)
			visible_roads.erase(key)
	for key in surfaces.keys():
		for dependency in surfaces[key].occlusion_keys:
			if changed.has(Vector2i(dependency.x, dependency.y)):
				surfaces.erase(key)
				break
	return changed


func clear_surfaces() -> void:
	surfaces.clear()
	visible_roads.clear()


func lamp_mask(sprite: Image, kind: int, direction: int) -> Image:
	var key := "%d:%d" % [kind, direction]
	if not masks.has(key):
		var mask := Image.create(sprite.get_width(), sprite.get_height(), false, Image.FORMAT_RGBA8)
		for y in sprite.get_height():
			for x in sprite.get_width():
				var pixel := sprite.get_pixel(x, y)
				if pixel == Color("e9dfba"):
					mask.set_pixel(x, y, HEADLIGHT)
				elif pixel == Color("ab423b"):
					mask.set_pixel(x, y, TAILLIGHT)
		masks[key] = mask
	return masks[key]


func surface(city: CityState, tile: Vector2i, enter: int, direction: int, lookup := Callable(), upload_texture := true) -> Dictionary:
	var key := Vector4i(tile.x, tile.y, road_key(city, tile, enter).z, direction)
	if surfaces.has(key):
		var cached := surfaces[key]
		if upload_texture and cached.texture == null:
			cached.texture = ImageTexture.create_from_image(cached.image)
		# Dictionary order tracks recent use. Evict one old surface, not the
		# entire working set when vehicles reach the next road tile.
		surfaces.erase(key)
		surfaces[key] = cached
		return cached
	prepared_receivers += 1
	var center := CityLifePaths.point(city, tile, enter, (enter + 2) % 4, 0.5, false)
	var world_origin := Vector2(tile)
	var bounds := Rect2i(Vector2i(center) - Vector2i(48, 48), Vector2i(96, 96))
	# Numeric world coordinates let the GPU draw the cone on sloping roads and decks.
	# HD receivers encode two local 12-bit coordinates in RGB and coverage in A.
	# This avoids a 16-byte float texel for every high-resolution light sample.
	var format := Image.FORMAT_RGBA8 if raster_scale > 1 else Image.FORMAT_RGBAF
	var image: Image = Image.create(96, 96, false, format) if raster_scale == 1 else null
	var occlusion_keys: Array[Vector3i] = []
	var patches: Array = []
	for step in 3:
		occlusion_keys.append(Vector3i(tile.x, tile.y, enter % 2))
		for road: Dictionary in _visible_road_patches(city, tile, enter, lookup):
			var destination: Vector2i = road.origin - bounds.position * raster_scale
			if raster_scale == 1:
				image.blit_rect_mask(road.image, road.image, Rect2i(Vector2i.ZERO, road.image.get_size()), destination)
			else:
				patches.append(road)
		var exit := direction
		if CityLifePaths.diagonal(city, tile):
			exit = CityLifePaths.paired_exit(city, tile, enter)
		elif direction >= 4:
			# Continue toward the same heading after a diagonal meets a junction.
			exit = (enter + 2) % 4
		if not CityLifePaths.connected(city, tile, exit):
			break
		tile += CityLifePaths.DIRECTIONS[exit]
		enter = (exit + 2) % 4
	if raster_scale > 1:
		image = NativeVisualRaster.headlight_receiver(Vector2i(96, 96) * raster_scale, bounds.position * raster_scale, patches, world_origin)
	# The instanced headlight renderer uploads directly into its texture array.
	# Avoid a second, unused GPU allocation for every prepared receiver.
	var draw_rect := image.get_used_rect().grow(1).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var result := {"draw_rect": draw_rect, "image": image, "texture": ImageTexture.create_from_image(image) if upload_texture else null, "origin": bounds.position,
		"occlusion_keys": occlusion_keys, "world_origin": world_origin}
	# Direct array uploads avoid a duplicate ImageTexture. Reuse that saved
	# allocation for a larger, bounded CPU working set.
	# RGBA8 uses one quarter of the classic float receiver's bytes per texel.
	var surface_limit := SURFACE_LIMIT * (8 if raster_scale > 1 and not upload_texture else 4 if raster_scale > 1 else 1) / (raster_scale * raster_scale)
	if raster_scale > 1 and not upload_texture:
		# An all-car scene must fit: otherwise cold preparation could evict
		# its own inputs indefinitely before the complete frame is published.
		surface_limit = maxi(surface_limit, CityLifeController.MAX_FIGURES)
	while surfaces.size() >= surface_limit:
		surfaces.erase(surfaces.keys()[0])
	surfaces[key] = result
	return result


static func _encode_receiver(target: Image, source: Image, destination: Vector2i, world_origin: Vector2) -> void:
	NativeVisualRaster.encode_receiver(target, source, destination, world_origin)


func _visible_road_patches(city: CityState, tile: Vector2i, enter: int, lookup: Callable) -> Array:
	var key := road_key(city, tile, enter)
	if visible_roads.has(key):
		return visible_roads[key]
	var occluders: Array = lookup.call(tile, enter) if lookup.is_valid() else []
	var patches := _road_patches(city, tile, enter)
	var bounds := Rect2i()
	for road: Dictionary in patches:
		var part := Rect2i(road.origin, road.image.get_size())
		bounds = bounds.merge(part) if bounds.has_area() else part
	occluders = CityLifeCanvas.scaled_occluders(occluders, raster_scale, Rect2i(bounds.position / raster_scale, bounds.size / raster_scale))
	var result: Array = []
	for road: Dictionary in patches:
		var pixels: Image = road.image.duplicate()
		var road_bounds := Rect2i(road.origin, pixels.get_size())
		for occluder: Dictionary in occluders:
			var overlap := road_bounds.intersection(Rect2i(occluder.origin, occluder.image.get_size()))
			if not overlap.has_area():
				continue
			var mask: Image = occluder.image.get_region(Rect2i(overlap.position - occluder.origin, overlap.size))
			var clear := Image.create(overlap.size.x, overlap.size.y, false, Image.FORMAT_RGBAF)
			pixels.blit_rect_mask(clear, mask, Rect2i(Vector2i.ZERO, overlap.size), overlap.position - road_bounds.position)
		result.append({"image": pixels, "origin": road.origin})
	visible_roads[key] = result
	return result


func cached_sprite_shear(city: CityState, tile: Vector2i, enter: int, exit: int) -> float:
	var key := Vector4i(tile.x, tile.y, enter, exit)
	if not sprite_shears.has(key):
		sprite_shears[key] = CityLifePaths.sprite_shear(city, tile, enter, exit)
	return sprite_shears[key]


func cached_vehicle_world(city: CityState, figure: CityLifeController.Figure) -> Vector2:
	var key := Vector4i(figure.tile.x, figure.tile.y, figure.enter, figure.exit)
	if not vehicle_planes.has(key):
		var origin := _project(city, figure.tile, Vector2.ZERO, 0.0)
		vehicle_planes[key] = Vector4(origin.x, origin.y, CityLifePaths.edge_height(city, figure.tile, figure.enter), CityLifePaths.edge_height(city, figure.tile, figure.exit))
	var plane := vehicle_planes[key]
	var altitude := lerpf(plane.z, plane.w, figure.progress)
	var local := figure.position - (Vector2(plane.x, plane.y) + Vector2(0.0, -altitude * 12.0))
	return Vector2(figure.tile) + Vector2(local.x / 32.0 + local.y / 16.0, local.y / 16.0 - local.x / 32.0)


static func vehicle_world(city: CityState, figure: CityLifeController.Figure) -> Vector2:
	var altitude := lerpf(CityLifePaths.edge_height(city, figure.tile, figure.enter),
		CityLifePaths.edge_height(city, figure.tile, figure.exit), figure.progress)
	var local := figure.position - _project(city, figure.tile, Vector2.ZERO, altitude)
	return Vector2(figure.tile) + Vector2(local.x / 32.0 + local.y / 16.0, local.y / 16.0 - local.x / 32.0)


func _road_patches(city: CityState, tile: Vector2i, enter: int) -> Array:
	var key := road_key(city, tile, enter)
	if roads.has(key):
		return roads[key]
	var patches: Array = []
	if CityLifePaths.diagonal(city, tile):
		patches = _diagonal_patch(city, tile, enter, raster_scale)
		roads[key] = patches
		return patches
	var ports := CityLifePaths.ports(city, tile)
	var exit := (enter + 2) % 4
	if not ports & (1 << exit):
		for direction in 4:
			if direction != enter and ports & (1 << direction) and CityLifePaths.can_turn(city, tile, enter, direction):
				exit = direction
				break
	var height := (CityLifePaths.edge_height(city, tile, enter) + CityLifePaths.edge_height(city, tile, exit)) * 0.5
	for direction in 4:
		if not ports & (1 << direction) or (direction != enter and not CityLifePaths.can_turn(city, tile, enter, direction)):
			continue
		var forward: Vector2 = FORWARD[direction]
		var side := Vector2(-forward.y, forward.x)
		var center := _project(city, tile, Vector2.ZERO, height)
		var end := _project(city, tile, forward * 0.5, CityLifePaths.edge_height(city, tile, direction))
		var across := Vector2((side.x - side.y) * 8.0, (side.x + side.y) * 4.0)
		var transform := Transform2D(end - center, across, center - across * 0.5)
		if absf(transform.determinant()) < 0.01:
			continue
		var bounds := Rect2(transform.origin, Vector2.ZERO)
		for uv in [Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
			bounds = bounds.expand(transform * uv)
		var inverse := transform.affine_inverse()
		var raster := Rect2i(bounds.grow(1.0))
		raster = Rect2i(raster.position * raster_scale, raster.size * raster_scale)
		var pixels := NativeVisualRaster.road_patch(raster, inverse, raster_scale, Vector2(tile),
			Vector2.ZERO, forward * 0.5, side * 0.5, false)
		patches.append({"origin": raster.position, "image": pixels})
	roads[key] = patches
	return patches


static func road_key(city: CityState, tile: Vector2i, enter: int) -> Vector3i:
	# The central highway curve has two separate carriageways, even on one axis.
	return Vector3i(tile.x, tile.y, enter if CityLifePaths.diagonal(city, tile) else enter % 2)


static func _diagonal_patch(city: CityState, tile: Vector2i, enter: int, raster_scale := 1) -> Array:
	var exit := CityLifePaths.paired_exit(city, tile, enter)
	var a := Vector2(CityLifePaths.DIRECTIONS[enter]) * 0.5
	var b := Vector2(CityLifePaths.DIRECTIONS[exit]) * 0.5
	var along := b - a
	var side := Vector2(-along.y, along.x).normalized() * 0.5
	var start := _project(city, tile, a, CityLifePaths.edge_height(city, tile, enter))
	var end := _project(city, tile, b, CityLifePaths.edge_height(city, tile, exit))
	var across := Vector2((side.x - side.y) * 16, (side.x + side.y) * 8)
	var transform := Transform2D(end - start, across, start - across * 0.5)
	if absf(transform.determinant()) < 0.01:
		return []
	var bounds := Rect2(transform * Vector2(-1, 0), Vector2.ZERO)
	for uv in [Vector2(2, 0), Vector2(2, 1), Vector2(-1, 1)]:
		bounds = bounds.expand(transform * uv)
	var raster := Rect2i(bounds.grow(1.0))
	raster = Rect2i(raster.position * raster_scale, raster.size * raster_scale)
	var inverse := transform.affine_inverse()
	var pixels := NativeVisualRaster.road_patch(raster, inverse, raster_scale, Vector2(tile), a, along, side, true)
	return [{"origin": raster.position, "image": pixels}]


static func _project(city: CityState, tile: Vector2i, offset: Vector2, altitude: float) -> Vector2:
	return Vector2(48 + (city.map_size + tile.x - tile.y) * 16, 520 + (tile.x + tile.y) * 8) \
		+ Vector2((offset.x - offset.y) * 16.0, (offset.x + offset.y) * 8.0 - altitude * 12.0)
