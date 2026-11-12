class_name CityCollapseEffects
extends RefCounted
## Short-lived old artwork, captured before renderer invalidation. No city writes.

const SHADER := preload("res://src/view/disasters/collapse.gdshader")
const LIMIT := 64
var pending: Dictionary = {}
var playing: Array[Dictionary] = []


static func style(sprite_id: int) -> int:
	var id := posmod(sprite_id, 500)
	if id >= 112 or sprite_id >= ExpandedRules.FIRST_SPRITE:
		return 2 # Building: small sink and a few artwork-colored fragments.
	if id >= 73 and id <= 107:
		return 1 # Raised highway/bridge: short sink, no disassembly.
	return 0 # Flat networks: dust and fade only.


static func is_structure(sprite_id: int) -> bool:
	var id := posmod(sprite_id, 500)
	return (id >= 14 and id <= 255) or (sprite_id >= ExpandedRules.FIRST_SPRITE \
		and sprite_id < ExpandedRules.FIRST_SPRITE + 1500)


func prepare(owner: CityDisasterEffects, events: Array[EffectEvent]) -> void:
	pending.clear()
	owner._sync_city()
	if not owner.active() or not owner.app.preferences.visual_enhancements.disaster_dust:
		return
	var app := owner.app
	var view := app.static_render.city_view_size()
	var divisor: int = CityIsometricRenderer.view_configuration(view).divisor
	var archive := app.static_render.sprite_archive_for_view(view)
	var seen := {}
	# Liftoff already retains and animates its artwork in the opposite direction.
	for event in events:
		if event.type == CityEffectTiming.LAUNCH_ARCOLOGY:
			seen[event.depth_point if event.depth_point.x >= 0 else event.point] = true
	for event in events:
		if not CityDisasterEffects.is_dust(event):
			continue
		var tile := event.depth_point if event.depth_point.x >= 0 else event.point
		if seen.has(tile) or pending.size() + playing.size() >= LIMIT:
			continue
		seen[tile] = true
		var at := CityDisasterEffects.ground_point(app.document_state.city, tile, event.altitude)
		if not owner._visible(tile, at):
			continue
		var order := (tile.x + tile.y) * app.document_state.city.map_size + tile.y
		var bounds := Rect2i(Vector2i(at) - Vector2i(160, 400), Vector2i(320, 480))
		for command in app.moving_sprites.static_occlusion_candidates(bounds):
			if command.depth_order != order or not is_structure(command.sprite_id):
				continue
			var sprite := archive.find_sprite(command.sprite_id)
			if sprite == null:
				continue
			var decoded := sprite.create_image(app.asset_state.palette)
			if not decoded.ok:
				continue
			var image: Image = decoded.image
			if archive.high_resolution.has(command.sprite_id) and app.render_caches.region_cache != null:
				image = archive.high_resolution[command.sprite_id].image.duplicate()
			if command.flip:
				image.flip_x()
			var size := command.size * divisor
			if image.get_size() != size:
				image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
			pending[tile] = {"image": image, "origin": Vector2(command.position * divisor),
				"style": style(command.sprite_id), "water": app.document_state.city.is_water(tile.x, tile.y)}
			break


func start(owner: CityDisasterEffects, tile: Vector2i, location: Vector2, side: float, delay: float, simulation: bool) -> bool:
	if not pending.has(tile) or playing.size() >= LIMIT:
		return false
	var entry: Dictionary = pending[tile]
	pending.erase(tile)
	owner._ensure_canvas()
	var image: Image = entry.image
	var padding := Vector2(56, 16)
	var extent := Vector2(image.get_size()) + padding * 2.0 + Vector2(0, 24)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = owner._texture
	sprite.scale = extent / Vector2(CityDisasterEffects.EXTENT)
	sprite.position = entry.origin - padding
	var material := ShaderMaterial.new()
	material.shader = SHADER
	sprite.material = material
	material.set_shader_parameter("artwork", ImageTexture.create_from_image(image))
	material.set_shader_parameter("extent", extent)
	material.set_shader_parameter("art_size", Vector2(image.get_size()))
	material.set_shader_parameter("art_origin", padding)
	material.set_shader_parameter("ground", location - sprite.position)
	material.set_shader_parameter("footprint", side)
	material.set_shader_parameter("kind", entry.style)
	material.set_shader_parameter("water", entry.water)
	material.set_shader_parameter("violent", simulation)
	material.set_shader_parameter("seed", float(posmod(tile.x * 73 + tile.y * 37, 101)))
	owner.canvas.add_child(sprite)
	playing.append({"sprite": sprite, "material": material, "tile": tile, "age": -delay,
		"duration": 2.2 if entry.style == 2 else 1.1, "user_action": not simulation,
		"bounds": Rect2i(Vector2i(sprite.position), Vector2i(extent)), "signature": []})
	return true


func process(owner: CityDisasterEffects, delta: float, frozen: bool) -> void:
	# All event batches of one edit/tick are delivered synchronously.
	pending.clear()
	if not owner.app.preferences.visual_enhancements.disaster_dust:
		clear()
		return
	for i in range(playing.size() - 1, -1, -1):
		var entry := playing[i]
		if not frozen or entry.user_action:
			entry.age += delta
		if entry.age >= entry.duration:
			entry.sprite.queue_free()
			playing.remove_at(i)
			continue
		# Retain the intact structure during the source event's short delay.
		entry.sprite.visible = true
		entry.material.set_shader_parameter("age", maxf(0.0, entry.age))
		entry.material.set_shader_parameter("motion", owner.app.preferences.visual_enhancements.disaster_motion)
		entry.material.set_shader_parameter("strength", owner.app.preferences.visual_enhancements.disaster_strength)
		owner.app.map_view.layers._apply_environment(entry.material)
		var signature := [owner.app.static_render_state.epoch, owner.app.static_render.city_view_size()]
		if entry.signature != signature:
			entry.signature = signature
			var mask := owner.app.moving_sprites.effect_occluder_mask(entry.bounds.position, entry.bounds.size,
				entry.tile, owner.app.static_render.city_view_size())
			entry.material.set_shader_parameter("has_foreground", mask != null)
			if mask != null:
				entry.material.set_shader_parameter("foreground", ImageTexture.create_from_image(mask))


func invalidate() -> void:
	for entry in playing:
		entry.signature = []


func clear() -> void:
	pending.clear()
	for entry in playing:
		entry.sprite.queue_free()
	playing.clear()
