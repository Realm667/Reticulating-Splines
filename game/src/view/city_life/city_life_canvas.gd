class_name CityLifeCanvas
extends Node2D
## Sparse artwork atlas. Tiny sprites are masked by cached silhouettes.

@warning_ignore_start("integer_division")

const SHADER := preload("res://src/view/city_life/city_life.gdshader")
const MAX_TEXTURE_EDGE := 4096
var atlas := CityLifeAtlas.new()
var gpu: CityLifeGpu
var gpu_enabled := DisplayServer.get_name() != "headless"
var interpolation := 1.0
var _entries: Array[Dictionary] = []
var _gpu_entries: Dictionary[CityLifeController.Figure, Dictionary] = {}
var _sprite_sizes: Dictionary[Image, Vector2i] = {}
var image: Image:
	get: return atlas.image
var texture: ImageTexture:
	get: return gpu.artwork if gpu != null else atlas.texture
var source_bounds := Rect2i()
var lights := CityLifeLights.new()
var emission: Image:
	get: return atlas.emission
var emission_texture: ImageTexture:
	get: return gpu.emission if gpu != null else atlas.emission_texture
var road_layer: Node2D
var _light_night := -1.0
var _light_preparation_cursor := 0
var _light_occluders: Dictionary[Vector3i, Array] = {}
var _occluders: Dictionary[Vector3i, Array] = {}
var _occluder_bounds: Dictionary[Vector3i, Rect2i] = {}
var _occlusion_signature: Array = []
var _visible_regions: Array[Vector2i] = []
var _emission_active := false
var include_cached_regions := false


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	show_behind_parent = true
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	material = shader_material


func _draw() -> void:
	if gpu == null and texture != null:
		for index in atlas.destinations.size():
			draw_texture_rect_region(texture, atlas.destinations[index], atlas.sources[index])


func render(app: CityApplication, figures: Array, sprites: CityLifeSprites, preparation_budget_usec := 0) -> bool:
	var previous_bounds := source_bounds
	var preparation_usec := 0
	var source_art := app.asset_state.asset_source.assets.visual_artwork if app.asset_state.asset_source != null else null
	var raster_scale := source_art.city_life_scale if source_art != null else 1
	if lights.raster_scale != raster_scale:
		lights.set_raster_scale(raster_scale)
		if road_layer != null:
			road_layer.free()
			road_layer = null
	if sprites.set_artwork(source_art):
		_sprite_sizes.clear()
		_gpu_entries.clear()
		if gpu != null:
			for node in gpu.groups + gpu.emissions:
				if is_instance_valid(node):
					node.queue_free()
			gpu = null
		atlas = CityLifeAtlas.new()
	var map := app.map_view
	var bounds := Rect2i(map.visible_source_rect()).grow(32)
	if not supports_view(map.visible_source_rect()):
		hide()
		return true
	var light_active := app.visual_environment.night > 0.0 and VisualEnhancementOptions.detail_lights_visible(app.preferences.visual_enhancements, map.zoom_factor)
	if road_layer == null:
		road_layer = CityLifeHeadlights.new()
		(road_layer as CityLifeHeadlights).raster_scale = raster_scale
		road_layer.show_behind_parent = true
		add_child(road_layer)
	if light_active != _emission_active:
		_emission_active = light_active
		(material as ShaderMaterial).set_shader_parameter("vehicle_has_emission", light_active)
	source_bounds = bounds
	var city := app.document_state.city
	# Road inclination is also used by unlit vehicles. Reuse it until the
	# shared geometry tracker reports an edit, rotation or replacement city.
	lights.sync_geometry(city)
	# Region publications also change while panning an unchanged city. Their
	# affected silhouettes are invalidated separately by the map renderer.
	var regions := app.render_caches.region_cache
	var source: RefCounted = regions if regions != null else map.city_source
	# Traffic revisions do not change silhouettes. Region publications report
	# the changed bounds; only a replacement layout needs a complete reset.
	var layout: Variant = regions._layout_generation if regions != null else app.render_caches.static_visual_signature
	var signature := [app.document_state.city.document.get_instance_id(), app.static_render_state.epoch,
		source, app.static_render.city_view_size(), layout]
	if signature != _occlusion_signature:
		_gpu_entries.clear()
		_occluders.clear()
		_occluder_bounds.clear()
		_light_occluders.clear()
		lights.clear_surfaces()
		_occlusion_signature = signature
	_sync_visible_regions(app.render_caches.region_cache)
	_trim_working_set()
	figures.sort_custom(func(a: CityLifeController.Figure, b: CityLifeController.Figure) -> bool:
		return a.position.y < b.position.y)
	road_layer.visible = light_active
	if _gpu_entries.size() > CityLifeController.MAX_FIGURES + 64:
		var active: Dictionary[CityLifeController.Figure, bool] = {}
		for figure: CityLifeController.Figure in figures:
			active[figure] = true
		for figure in _gpu_entries.keys():
			if not active.has(figure):
				_gpu_entries.erase(figure)
	_entries.clear()
	var entries := _entries
	var receiver_inputs: Dictionary[int, Dictionary] = {}
	for figure: CityLifeController.Figure in figures:
		var preparation_started := Time.get_ticks_usec()
		var cold := not _occluders.has(Vector3i(figure.tile.x, figure.tile.y, figure.enter % 2))
		var receivers := lights.prepared_receivers
		if light_active and not figure.walking:
			receiver_inputs[figure.id] = lights.surface(city, figure.tile, figure.enter, figure.direction,
				func(tile: Vector2i, enter: int) -> Array: return _light_candidates(app, tile, enter), false)
		var sprite := sprites.sprite(figure.walking, figure.variant, figure.direction, int(figure.distance * 8.0) % 2, figure.vehicle_kind)
		if not _sprite_sizes.has(sprite):
			_sprite_sizes[sprite] = sprite.get_size()
		var size := _sprite_sizes[sprite]
		var origin := Vector2i(figure.position.round()) - Vector2i(size.x / 2, size.y - 1)
		if not source_bounds.intersects(Rect2i(origin, size)):
			if lights.prepared_receivers != receivers:
				preparation_usec += Time.get_ticks_usec() - preparation_started
			if preparation_budget_usec > 0 and preparation_usec >= preparation_budget_usec:
				return _pending_frame(app, previous_bounds)
			continue
		var candidates := _candidates(app, figure.tile, figure.enter)
		var opacity := figure.opacity()
		var shear := 0.0 if figure.walking else lights.cached_sprite_shear(city, figure.tile, figure.enter, figure.exit)
		if gpu_enabled:
			var entry: Dictionary = _gpu_entries.get(figure, {})
			if entry.is_empty():
				entry = {"figure": figure}
				_gpu_entries[figure] = entry
			entry.sprite = sprite
			entry.origin = origin
			entry.occluders = candidates
			entry.opacity = opacity
			entry.shear = shear
			entries.append(entry)
		else:
			var mask: Image = sprites.lamp_image(sprite, lights, figure.vehicle_kind, figure.direction) if light_active and not figure.walking else null
			entries.append({"sprite": sprite, "origin": origin, "occluders": candidates, "opacity": opacity, "lamps": mask, "figure": figure, "shear": shear,
				"master": sprites.master_image(sprite), "master_lamps": sprites.lamp_image(sprite, lights, figure.vehicle_kind, figure.direction, true) if mask != null else null})
		if cold or lights.prepared_receivers != receivers:
			preparation_usec += Time.get_ticks_usec() - preparation_started
		if preparation_budget_usec > 0 and preparation_usec >= preparation_budget_usec:
			return _pending_frame(app, previous_bounds)
	# Publish complete batches only; cold inputs and GPU pages are prepared
	# in bounded steps while the previous draw remains available.
	if preparation_budget_usec > 0:
		if gpu_enabled:
			if gpu == null:
				gpu = CityLifeGpu.new()
				gpu.prepare(sprites, lights)
				return _pending_frame(app, previous_bounds)
			if gpu.groups.size() * CityLifeGpu.GROUP < figures.size():
				gpu.add_group(self)
				return _pending_frame(app, previous_bounds)
		if light_active:
			var vehicles := 0
			for figure: CityLifeController.Figure in figures:
				vehicles += int(not figure.walking)
			if (road_layer as CityLifeHeadlights).groups.size() * CityLifeHeadlights.GROUP_SIZE < vehicles:
				(road_layer as CityLifeHeadlights)._add_group()
				return _pending_frame(app, previous_bounds)
	if light_active:
		(road_layer as CityLifeHeadlights).render(city, figures, lights, source_bounds.position,
			func(tile: Vector2i, enter: int) -> Array: return _light_candidates(app, tile, enter), receiver_inputs,
			gpu_enabled and interpolation < 1.0 and bool(app.preferences.visual_enhancements.traffic_vehicles_enabled))
	if gpu_enabled:
		if gpu == null:
			gpu = CityLifeGpu.new()
			gpu.prepare(sprites, lights)
		gpu.render(self, entries)
	else:
		atlas.compose(bounds, entries, light_active)
	if light_active and gpu == null:
		(material as ShaderMaterial).set_shader_parameter("vehicle_emission", emission_texture)
	sync_view(app)
	show()
	queue_redraw()
	return true


func _pending_frame(app: CityApplication, previous_bounds: Rect2i) -> bool:
	source_bounds = previous_bounds
	interpolation = 1.0
	sync_view(app)
	return false


static func supports_view(bounds: Rect2) -> bool:
	var extent := bounds.size.ceil() + Vector2(64, 64)
	return extent.x > 0.0 and extent.y > 0.0 and extent.x <= MAX_TEXTURE_EDGE and extent.y <= MAX_TEXTURE_EDGE


func sync_view(app: CityApplication) -> void:
	var view_scale := app.map_view.camera._view_scale()
	position = Vector2(source_bounds.position) * view_scale + app.map_view.camera._draw_offset(view_scale)
	scale = Vector2(view_scale, view_scale)
	app.map_view.layers._apply_environment(material as ShaderMaterial)
	if gpu != null:
		gpu.sync(app, _emission_active, interpolation)
	var allowed := VisualEnhancementOptions.detail_lights_visible(app.preferences.visual_enhancements, app.map_view.zoom_factor)
	(material as ShaderMaterial).set_shader_parameter("vehicle_has_emission", allowed and _emission_active)
	if road_layer != null:
		road_layer.visible = allowed and app.visual_environment.night > 0.0
		(road_layer as CityLifeHeadlights).set_interpolation(interpolation if app.preferences.visual_enhancements.traffic_vehicles_enabled else 1.0)
	if road_layer != null and (app.visual_environment.night if allowed else 0.0) != _light_night:
		_light_night = app.visual_environment.night if allowed else 0.0
		(road_layer as CityLifeHeadlights).set_night(_light_night)


func prepare_lights(app: CityApplication, figures: Array, budget_usec := 1500) -> void:
	if not gpu_enabled or road_layer == null or figures.is_empty() or app.visual_environment.night > 0.0:
		return
	if not VisualEnhancementOptions.detail_lights_visible(app.preferences.visual_enhancements, app.map_view.zoom_factor):
		return
	var started := Time.get_ticks_usec()
	var city := app.document_state.city
	lights.sync_geometry(city)
	var headlights := road_layer as CityLifeHeadlights
	var vehicles := 0
	for figure: CityLifeController.Figure in figures:
		vehicles += int(not figure.walking)
	if headlights.groups.size() * CityLifeHeadlights.GROUP_SIZE < vehicles:
		headlights._add_group()
		return
	# Use idle presentation frames to warm the next night. A small rotating
	# sample avoids rescanning the complete working set on every display frame.
	for index in mini(32, figures.size()):
		_light_preparation_cursor %= figures.size()
		var figure: CityLifeController.Figure = figures[_light_preparation_cursor]
		_light_preparation_cursor += 1
		if not figure.walking:
			var road := CityLifeLights.road_key(city, figure.tile, figure.enter)
			if not lights.surfaces.has(Vector4i(road.x, road.y, road.z, figure.direction)):
				lights.surface(city, figure.tile, figure.enter, figure.direction,
					func(tile: Vector2i, enter: int) -> Array: return _light_candidates(app, tile, enter), false)
		if Time.get_ticks_usec() - started >= budget_usec:
			break


func _candidates(app: CityApplication, tile: Vector2i, enter: int = 0) -> Array:
	var city := app.document_state.city
	var key := Vector3i(tile.x, tile.y, enter % 2)
	if _occluders.has(key):
		return _occluders[key]
	var center := CityLifePaths.point(city, tile, enter, (enter + 2) % 4, 0.5, false)
	var bounds := Rect2i(Vector2i(center) - Vector2i(32, 28), Vector2i(64, 48))
	var view := app.static_render.city_view_size()
	var archive := app.static_render.sprite_archive_for_view(view)
	var divisor := IsometricGeometry.view_configuration(view).divisor
	var depth := (tile.x + tile.y) * city.map_size + tile.y
	var id := city.building_id(tile.x, tile.y)
	var tunnel := id in [BuildingTileIds.TUNNEL_ENTRANCE_1, BuildingTileIds.TUNNEL_ENTRANCE_2]
	var own_structure := tunnel or (id >= BuildingTileIds.SUSPENSION_BRIDGE_1 and id <= BuildingTileIds.RAISING_BRIDGE_CLOSED) \
		or (id >= BuildingTileIds.HIGHWAY_STRAIGHT_1 and id <= BuildingTileIds.HIGHWAY_POWER_CROSSING_2) \
		or (id >= BuildingTileIds.HIGHWAY_SLOPE_1 and id <= BuildingTileIds.REINFORCED_HIGHWAY_BRIDGE)
	var section := CityLifePaths.section_origin(city, tile)
	var lower_crossing := id in [BuildingTileIds.HIGHWAY_ROAD_CROSSING_1, BuildingTileIds.HIGHWAY_ROAD_CROSSING_2] \
		and CityLifePaths.edge_height(city, tile, enter) < city.land_altitude(tile.x, tile.y) + 1.0
	var candidates: Array = []
	var commands := app.moving_sprites.static_occlusion_candidates(bounds)
	if include_cached_regions and app.render_caches.region_cache != null:
		commands = app.render_caches.region_cache.occlusion_candidates(bounds, true)
	for command in commands:
		var command_tile := Vector2i(command.depth_order % city.map_size, 0)
		command_tile = Vector2i(int(command.depth_order / city.map_size) - command_tile.x, command_tile.x)
		var own := own_structure and (command_tile == tile or (id >= BuildingTileIds.HIGHWAY_SLOPE_1 \
			and command.sprite_id % 500 == id and CityLifePaths.section_origin(city, command_tile) == section))
		# A diagonal highway is an open deck on pillars. Its multi-tile sprite
		# can sort after the car's supporting tile, but remains beneath it.
		if own and CityLifePaths.diagonal(city, tile):
			continue
		if command.depth_order <= depth and not own:
			continue
		var resource := app.moving_sprites.dynamic_sprite_resource(archive, command.sprite_id, command.flip, divisor, 1, true)
		if resource != null:
			var origin := Vector2i(command.position) * divisor
			var mask: Image = resource.image
			if own:
				if lower_crossing:
					mask = app.moving_sprites._dynamic_train_foreground_image(archive, command, divisor, mask)
				elif not tunnel:
					# The deck is beneath the car; its towers and rails remain foreground.
					var forward := Vector2(CityLifePaths.DIRECTIONS[enter])
					var opposite := (enter + 2) % 4
					var a := CityLifeLights._project(city, tile, forward * 0.5, CityLifePaths.edge_height(city, tile, enter))
					var b := CityLifeLights._project(city, tile, -forward * 0.5, CityLifePaths.edge_height(city, tile, opposite))
					mask = deck_foreground(mask, origin, (a + b) * 0.5, (b.y - a.y) / (b.x - a.x))
			candidates.append({"origin": origin, "image": mask})
	_occluder_bounds[key] = bounds
	# The figure shader samples exactly this 128-pixel mask. Do not compose
	# complete tall buildings only to crop them again in CityLifeGpu.render().
	var clip := Rect2i(bounds.position - Vector2i(32, 32), Vector2i(128, 128)) if gpu_enabled and not include_cached_regions else Rect2i()
	_occluders[key] = merged_occluders(candidates, clip)
	return _occluders[key]


func _sync_visible_regions(cache: CityRegionCache) -> void:
	if cache == null:
		_visible_regions.clear()
		return
	# Queries include visible regions only. Publications report arriving regions;
	# departing regions must also release their cached silhouettes.
	var departed: Array[Rect2i] = []
	for key in _visible_regions:
		if not cache.visible_keys.has(key):
			departed.append(Rect2i(key * cache.region_edge * cache.divisor,
				Vector2i.ONE * cache.region_edge * cache.divisor))
	invalidate_occlusion(departed)
	_visible_regions.assign(cache.visible)


func invalidate_occlusion(changes: Array[Rect2i]) -> void:
	if changes.is_empty() or _occluder_bounds.is_empty():
		return
	var invalidated := {}
	for key in _occluder_bounds:
		for changed in changes:
			if _occluder_bounds[key].intersects(changed):
				invalidated[key] = true
				break
	for key in invalidated:
		_occluders.erase(key)
		_occluder_bounds.erase(key)
		_light_occluders.erase(key)
		lights.visible_roads.erase(key)
		lights.visible_roads.erase(key + Vector3i(0, 0, 2))
	for key in lights.surfaces.keys():
		for dependency in lights.surfaces[key].occlusion_keys:
			if invalidated.has(dependency):
				lights.surfaces.erase(key)
				break


static func merged_occluders(candidates: Array, clip := Rect2i()) -> Array:
	if candidates.is_empty() or (candidates.size() == 1 and not clip.has_area()):
		return candidates
	# Keep the complete queried silhouettes, including pixels outside the query
	# rectangle. Cars on slopes and long buses can reach beyond that rectangle.
	var bounds := Rect2i(candidates[0].origin, candidates[0].image.get_size())
	for candidate: Dictionary in candidates:
		bounds = bounds.merge(Rect2i(candidate.origin, candidate.image.get_size()))
	if clip.has_area():
		bounds = bounds.intersection(clip)
	if not bounds.has_area():
		return []
	var mask := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	for candidate: Dictionary in candidates:
		mask.blend_rect(candidate.image, Rect2i(Vector2i.ZERO, candidate.image.get_size()), candidate.origin - bounds.position)
	return [{"origin": bounds.position, "image": mask}]


func _light_candidates(app: CityApplication, tile: Vector2i, enter: int) -> Array:
	var key := Vector3i(tile.x, tile.y, enter % 2)
	if _light_occluders.has(key):
		return _light_occluders[key]
	var center := CityLifePaths.point(app.document_state.city, tile, enter, (enter + 2) % 4, 0.5, false)
	var bounds := Rect2i(Vector2i(center) - Vector2i(32, 32), Vector2i(64, 64))
	var mask := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for candidate: Dictionary in _candidates(app, tile, enter):
		var part := Rect2i(candidate.origin, candidate.image.get_size()).intersection(bounds)
		if part.has_area():
			mask.blend_rect(candidate.image, Rect2i(part.position - candidate.origin, part.size), part.position - bounds.position)
	var candidates: Array = [{"origin": bounds.position, "image": mask}]
	_light_occluders[key] = candidates
	return candidates


static func deck_foreground(source: Image, origin: Vector2i, surface: Vector2, slope: float) -> Image:
	var mask := source.duplicate() as Image
	for x in mask.get_width():
		var cutoff := surface.y + (origin.x + x - surface.x) * slope - 2.0
		for y in mask.get_height():
			if origin.y + y >= cutoff:
				mask.set_pixel(x, y, Color.TRANSPARENT)
	return mask


static func stamp(destination: Image, offset: Vector2i, sprite: Image, origin: Vector2i, occluders: Array,
		opacity: float = 1.0, lamp_destination: Image = null, lamps: Image = null, clip := Rect2i()) -> void:
	if not clip.has_area():
		clip = Rect2i(Vector2i.ZERO, destination.get_size())
	var area := Rect2i(origin - offset, sprite.get_size()).intersection(clip)
	if not area.has_area():
		return
	if opacity == 1.0:
		# Native image blits preserve replacement order and alpha without a
		# GDScript callback for every opaque sprite pixel. Fades keep their exact
		# per-pixel alpha rounding below.
		var visible := visible_sprite(sprite, origin, occluders)
		var rect := Rect2i(area.position - origin + offset, area.size)
		destination.blit_rect_mask(sprite, visible, rect, area.position)
		if lamp_destination != null:
			if lamps == null:
				lamps = Image.create(sprite.get_width(), sprite.get_height(), false, Image.FORMAT_RGBA8)
				lamps.fill(Color.TRANSPARENT)
			lamp_destination.blit_rect_mask(lamps, visible, rect, area.position)
		return
	for y in sprite.get_height():
		for x in sprite.get_width():
			var color := sprite.get_pixel(x, y)
			if color.a == 0.0:
				continue
			var point := origin + Vector2i(x, y)
			var local := point - offset
			if not clip.has_point(local):
				continue
			if not hidden_at(point, occluders):
				color.a *= opacity
				destination.set_pixelv(local, color)
				if lamp_destination != null:
					var lamp := lamps.get_pixel(x, y) if lamps != null else Color.TRANSPARENT
					lamp.a *= opacity
					lamp_destination.set_pixelv(local, lamp)


static func visible_sprite(sprite: Image, origin: Vector2i, occluders: Array) -> Image:
	var visible := sprite
	var bounds := Rect2i(origin, sprite.get_size())
	for occluder: Dictionary in occluders:
		var overlap := bounds.intersection(Rect2i(occluder.origin, occluder.image.get_size()))
		if not overlap.has_area():
			continue
		if visible == sprite:
			visible = sprite.duplicate()
		var mask: Image = occluder.image.get_region(Rect2i(overlap.position - occluder.origin, overlap.size))
		var clear := Image.create(overlap.size.x, overlap.size.y, false, sprite.get_format())
		visible.blit_rect_mask(clear, mask, Rect2i(Vector2i.ZERO, overlap.size), overlap.position - origin)
	return visible


static func scaled_occluders(occluders: Array, raster_scale: int, clip := Rect2i()) -> Array:
	if raster_scale == 1:
		return occluders
	var result: Array = []
	for occluder: Dictionary in occluders:
		var bounds := Rect2i(occluder.origin, occluder.image.get_size())
		var area := bounds.intersection(clip) if clip.has_area() else bounds
		if not area.has_area():
			continue
		# Only enlarge pixels that the light receiver can actually sample.
		# A large foreground building must not allocate its full 4x image here.
		var mask: Image = occluder.image.get_region(Rect2i(area.position - bounds.position, area.size))
		mask.resize(mask.get_width() * raster_scale, mask.get_height() * raster_scale, Image.INTERPOLATE_NEAREST)
		result.append({"image": mask, "origin": area.position * raster_scale})
	return result


static func hidden_at(point: Vector2i, occluders: Array) -> bool:
	for occluder: Dictionary in occluders:
		var mask: Image = occluder.image
		var sample: Vector2i = point - occluder.origin
		if sample.x >= 0 and sample.y >= 0 and sample.x < mask.get_width() and sample.y < mask.get_height() \
				and mask.get_pixel(sample.x, sample.y).a > 0.0:
			return true
	return false


func _trim_working_set() -> void:
	if _occluders.size() > 4096:
		var removed := 0
		for key in _occluder_bounds.keys():
			if source_bounds.grow(96).intersects(_occluder_bounds[key]):
				continue
			_occluders.erase(key)
			_occluder_bounds.erase(key)
			_light_occluders.erase(key)
			removed += 1
			if removed >= 64:
				break
	for cache: Dictionary in [lights.roads, lights.visible_roads, lights.vehicle_planes, lights.sprite_shears, _light_occluders]:
		if cache.size() <= 4096:
			continue
		var removed := 0
		for key in cache.keys():
			var road := Vector3i(key.x, key.y, key.z % 2)
			if _occluder_bounds.has(road) and source_bounds.grow(96).intersects(_occluder_bounds[road]):
				continue
			cache.erase(key)
			removed += 1
			if removed >= 64:
				break
