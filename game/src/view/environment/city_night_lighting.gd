class_name CityNightLighting
extends RefCounted
## Presentation-only light buffers. Shares static meshes and authored brightmaps.

const EMISSION := preload("res://src/view/environment/night_emission.gdshader")
const EMISSION_PAGES := preload("res://src/view/environment/night_emission_pages.gdshader")
const BLUR := preload("res://src/view/environment/night_blur.gdshader")
const GLOW := preload("res://src/view/environment/night_glow.gdshader")
const PADDING := 24.0
var app: CityApplication
var buffers: Array[SubViewport] = []
var scene: Node2D
var output: TextureRect
var ground: CityNightGround
var ground_views: Dictionary[int, CityNightGround] = {}
var source: CityMapSource
var blur_rects: Array[TextureRect] = []
var copies: Array[CanvasItem] = []
var moving: CityDynamicSpriteCanvas
var life: LifeEmission
var moving_revision := -1
var fades := CityLightFade.new()
var detail_enabled := true
var moving_detail_enabled := true
var _warm_source: CityMapSource
var _warm_size := Vector2i.ZERO
var _warm_figure_groups := -1


func _init(application: CityApplication) -> void:
	app = application


func reset() -> void:
	fades.reset()
	source = null
	_warm_source = null
	_warm_size = Vector2i.ZERO
	_warm_figure_groups = -1
	moving_revision = -1
	for receiver in ground_views.values():
		receiver.reset()
		receiver.clock = 0.0


func process(active: bool, night: float, options: Dictionary, elapsed := 0.0, presentation_elapsed := 0.0) -> void:
	fades.advance(presentation_elapsed)
	detail_enabled = VisualEnhancementOptions.detail_lights_visible(options, app.map_view.zoom_factor)
	var enabled := active and night > 0.001 and app.map_view.city_source != null
	var glow := enabled and float(options.night_glow) > 0.0
	var prepare := active and detail_enabled and app.map_view.city_source != null and float(options.night_ground) > 0.0
	var prepare_glow := active and app.map_view.city_source != null and float(options.night_glow) > 0.0
	if output == null and not enabled and not prepare and not prepare_glow:
		return
	if output == null:
		_create()
	_select_ground(app.static_render.city_view_size())
	output.visible = glow
	for buffer in buffers:
		buffer.render_target_update_mode = SubViewport.UPDATE_ALWAYS if glow else SubViewport.UPDATE_DISABLED
	ground.sync(app, night * float(options.night_ground) / 100.0 if enabled and detail_enabled else 0.0, elapsed, prepare)
	var before: Control = app.visual_environment.clouds.layer
	if before == null:
		before = app.visual_environment.weather.layer
	if before == null:
		before = app.map_view.layers.overlay_layer
	if before != null:
		if ground.get_index() > before.get_index():
			app.map_view.move_child(ground, before.get_index())
		if output.get_index() > before.get_index():
			app.map_view.move_child(output, before.get_index())
	if not glow and not prepare_glow:
		return
	var map := app.map_view
	var bounds := map.camera._camera_rect()
	var padded := bounds.grow(PADDING)
	# Master windows can be smaller than a logical SC2K pixel. Retain their
	# screen resolution before the diffuse blur instead of dropping thin lamps.
	var archive := app.static_render.original_archive_for_view(app.static_render.city_view_size())
	var master_art := archive != null and not archive.high_resolution.is_empty()
	var emission_reduction := minf(1.0 if master_art else 0.5, (2048.0 if master_art else 1024.0) / maxf(padded.size.x, padded.size.y))
	var reduction := emission_reduction * 0.5
	var size := Vector2i((padded.size * reduction).ceil())
	var figures := app.city_life.canvas
	var figure_groups := figures.gpu.groups.size() if figures != null and figures.gpu != null else 0
	if not glow:
		if _warm_source == map.city_source and _warm_size == size and _warm_figure_groups == figure_groups:
			return
		# Render the real emission/blur path once while its output is hidden.
		# Keep the allocated targets and shaders for the first night; daytime
		# frames do no recurring off-screen glow work when the inputs are stable.
		for buffer in buffers:
			buffer.render_target_update_mode = SubViewport.UPDATE_ONCE
	_warm_source = map.city_source
	_warm_size = size
	_warm_figure_groups = figure_groups
	buffers[0].size = Vector2i((padded.size * emission_reduction).ceil())
	for index in range(1, buffers.size()):
		buffers[index].size = size
	var view_scale := map.camera._view_scale()
	var radius := maxf(0.65, view_scale * emission_reduction * 1.5)
	for index in blur_rects.size():
		blur_rects[index].size = Vector2(size)
		(blur_rects[index].material as ShaderMaterial).set_shader_parameter("radius", radius if index == 0 else radius * 0.5)
		(blur_rects[index].material as ShaderMaterial).set_shader_parameter("small_light_retention", 0.6 if master_art and index == 0 else 0.0)
	scene.scale = Vector2.ONE * view_scale * emission_reduction
	scene.position = (map.camera._draw_offset(view_scale) - padded.position) * emission_reduction
	if source != map.city_source:
		_rebuild(map.city_source)
	for copy in copies:
		(copy.material as ShaderMaterial).set_shader_parameter("artwork_animation_seconds", map.artwork_animation_seconds)
	_sync_moving()
	output.position = bounds.position
	output.size = bounds.size
	var shader := output.material as ShaderMaterial
	shader.set_shader_parameter("strength", night * float(options.night_glow) / 100.0 * 1.6)
	shader.set_shader_parameter("sample_scale", bounds.size * reduction / Vector2(size))
	shader.set_shader_parameter("sample_offset", Vector2.ONE * PADDING * reduction / Vector2(size))


func _select_ground(view_size: int) -> void:
	# Each original-art size has different foreground silhouettes. Keep its
	# finished receivers when zoom switches to another size, rather than reset.
	if not ground_views.has(view_size):
		var receiver := CityNightGround.new()
		receiver.fades = fades
		receiver.texture_budget = int(CityNightGround.MAX_TEXTURE_BYTES / 3.0)
		app.map_view.add_child(receiver)
		app.map_view.layers.ground_receivers.append(receiver)
		ground_views[view_size] = receiver
	var next: CityNightGround = ground_views[view_size]
	if ground == next:
		return
	if ground != null:
		next.clock = ground.clock
		ground.hide()
	ground = next
	app.map_view.layers._sync_base_layer()
	ground.signals.queue_redraw()


func invalidate_regions(changes: Array[Rect2i]) -> void:
	# An edit must also reach the currently hidden artwork-size variants.
	for receiver in ground_views.values():
		receiver.invalidate_regions(changes)


func invalidate_all() -> void:
	for receiver in ground_views.values():
		receiver.invalidate_all()
	# Non-current directions compare owned geometry when revisited. Explicit
	# style changes, however, must also invalidate those retained masks.
	for retained in app.visual_preparation.directions.values():
		for receiver in retained.lights.values():
			if receiver not in ground_views.values():
				receiver.invalidate_all()


func release_receiver(receiver: CityNightGround) -> void:
	if not is_instance_valid(receiver) or receiver.is_queued_for_deletion():
		return
	app.map_view.layers.ground_receivers.erase(receiver)
	receiver.hide()
	receiver.queue_free()


func _create() -> void:
	_select_ground(app.static_render.city_view_size())
	for i in 3:
		var buffer := SubViewport.new()
		buffer.disable_3d = true
		buffer.size = Vector2i(8, 8)
		buffer.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		buffer.transparent_bg = true
		buffer.use_hdr_2d = app.map_view.get_viewport().use_hdr_2d
		buffer.world_2d = World2D.new()
		app.map_view.add_child(buffer)
		buffers.append(buffer)
		if i == 0:
			scene = Node2D.new()
			buffer.add_child(scene)
		else:
			var rect := TextureRect.new()
			rect.texture = buffers[i - 1].get_texture()
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var shader := ShaderMaterial.new()
			shader.shader = BLUR
			shader.set_shader_parameter("direction", Vector2.RIGHT if i == 1 else Vector2.DOWN)
			rect.material = shader
			buffer.add_child(rect)
			blur_rects.append(rect)
	output = TextureRect.new()
	output.name = "NightLightGlow"
	output.mouse_filter = Control.MOUSE_FILTER_IGNORE
	output.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	output.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	output.texture = buffers.back().get_texture()
	var material := ShaderMaterial.new()
	material.shader = GLOW
	output.material = material
	app.map_view.add_child(output)
	moving = CityDynamicSpriteCanvas.new()
	var moving_material := ShaderMaterial.new()
	moving_material.shader = preload("res://src/view/environment/night_moving_emission.gdshader")
	moving.material = moving_material
	scene.add_child(moving)
	life = LifeEmission.new()
	life.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var life_material := ShaderMaterial.new()
	life_material.shader = EMISSION
	life_material.set_shader_parameter("has_emission", true)
	life.material = life_material
	scene.add_child(life)
	_warm_glow(material)


func _warm_glow(material: ShaderMaterial) -> void:
	# Daytime preparation renders emission and blur, but the final additive
	# output stays hidden. Exercise that last pipeline before the first night.
	var warm := SubViewport.new()
	warm.disable_3d = true
	warm.size = Vector2i(64, 64)
	warm.transparent_bg = true
	warm.use_hdr_2d = app.map_view.get_viewport().use_hdr_2d
	warm.world_2d = World2D.new()
	warm.render_target_update_mode = SubViewport.UPDATE_ONCE
	app.map_view.add_child(warm)
	var rect := TextureRect.new()
	rect.texture = output.texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = Vector2(64, 64)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shader := material.duplicate() as ShaderMaterial
	shader.set_shader_parameter("strength", 1.0)
	shader.set_shader_parameter("sample_scale", Vector2.ONE)
	shader.set_shader_parameter("sample_offset", Vector2.ZERO)
	rect.material = shader
	warm.add_child(rect)
	RenderingServer.frame_post_draw.connect(warm.queue_free, CONNECT_ONE_SHOT)


func _rebuild(value: CityMapSource) -> void:
	var previous := source
	source = value
	# Region snapshots retain unchanged immutable mesh descriptors. Only update
	# changed light geometry instead of recreating every canvas item and material.
	if previous != null and previous.texture == null and value.texture == null \
			and previous.tiles.is_empty() and value.tiles.is_empty() \
			and copies.all(func(item: CanvasItem) -> bool: return item is MeshInstance2D):
		while copies.size() < value.meshes.size():
			_register(MeshInstance2D.new(), null)
		for index in copies.size():
			var mesh := copies[index] as MeshInstance2D
			mesh.visible = index < value.meshes.size()
			if not mesh.visible:
				# Retain the cheap node, release hidden geometry and atlas references.
				mesh.mesh = null
				mesh.texture = null
				apply_region_emission(mesh.material as ShaderMaterial, null)
				continue
			var entry := value.meshes[index]
			if index < previous.meshes.size() and entry == previous.meshes[index] and entry.immutable:
				continue
			mesh.mesh = entry.mesh
			mesh.texture = entry.texture
			mesh.position = entry.position
			mesh.scale = Vector2.ONE * entry.divisor
			apply_region_emission(mesh.material as ShaderMaterial, entry)
		scene.move_child(moving, -1)
		scene.move_child(life, -1)
		return
	for copy in copies:
		copy.free()
	copies.clear()
	if value.texture != null:
		_add_texture(value.texture, value.emission, Vector2.ZERO, Vector2(value.size))
	for tile in value.tiles:
		_add_texture(tile.texture, tile.emission, tile.position, tile.size)
	for entry in value.meshes:
		var mesh := MeshInstance2D.new()
		mesh.mesh = entry.mesh
		mesh.texture = entry.texture
		mesh.position = entry.position
		mesh.scale = Vector2.ONE * entry.divisor
		_register(mesh, entry.emission)
		apply_region_emission(mesh.material as ShaderMaterial, entry)
	scene.move_child(moving, -1)
	scene.move_child(life, -1)


static func apply_region_emission(material: ShaderMaterial, entry: CityMapSource.MeshEntry) -> void:
	if entry != null and entry.texture_pages != null:
		entry.texture_pages.apply(material, EMISSION_PAGES)
		material.set_shader_parameter("has_emission", entry.texture_pages.emission != null)
		material.set_shader_parameter("emission", null)
	else:
		material.shader = EMISSION
		# Hidden/replaced regions must release the resident texture arrays too.
		for parameter in ["region_atlas_pages", "region_emission_pages", "region_season_pages"]:
			material.set_shader_parameter(parameter, null)
		material.set_shader_parameter("emission", entry.emission if entry != null else null)
		material.set_shader_parameter("has_emission", entry != null and entry.emission != null)


func _sync_moving() -> void:
	var canvas := app.map_view.layers.dynamic_canvas
	moving.visible = canvas != null and canvas.visible
	if moving.visible and (moving_revision != canvas.visual_revision or moving_detail_enabled != detail_enabled):
		moving_detail_enabled = detail_enabled
		moving_revision = canvas.visual_revision
		var visible_art: Array[CityDynamicVisual] = canvas.visuals.filter(func(visual: CityDynamicVisual) -> bool:
			return not visual.shadow and not visual.transparent_shadow and (detail_enabled or not visual.vehicle_light))
		moving.set_visuals(visible_art, 1.0, Vector2.ZERO)
	var figures := app.city_life.canvas
	life.figures = figures
	life.visible = detail_enabled and figures != null and figures.visible and figures.texture != null
	if life.visible:
		life.queue_redraw()


func _add_texture(texture: Texture2D, emission: Texture2D, position: Vector2, size: Vector2) -> void:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.position = position
	rect.size = size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_register(rect, emission)


func _register(item: CanvasItem, emission: Texture2D) -> void:
	var material := ShaderMaterial.new()
	material.shader = EMISSION
	material.set_shader_parameter("emission", emission)
	material.set_shader_parameter("has_emission", emission != null)
	item.material = material
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(item)
	copies.append(item)


class LifeEmission extends Node2D:
	var figures: CityLifeCanvas


	func _draw() -> void:
		if not is_instance_valid(figures) or not figures.visible or figures.texture == null:
			return
		if figures.gpu != null:
			figures.gpu.sync_emission(self)
			return
		position = Vector2.ZERO
		var atlas := figures.atlas
		# The atlas packs occupied squares; its texture coordinates are not
		# world positions. Match the vehicle canvas before blurring its lamps.
		# City life updates after lighting, so read the matching texture and
		# rectangles together at draw time, including atlas growth and panning.
		(material as ShaderMaterial).set_shader_parameter("emission", figures.emission_texture)
		for index in atlas.destinations.size():
			var destination := Rect2i(atlas.destinations[index])
			destination.position += figures.source_bounds.position
			draw_texture_rect_region(atlas.texture, destination, atlas.sources[index])
