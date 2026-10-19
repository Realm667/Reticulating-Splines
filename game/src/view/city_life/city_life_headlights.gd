class_name CityLifeHeadlights
extends Node2D
## Stable texture-array slots keep moving headlights in a few GPU draw calls.
@warning_ignore_start("integer_division")

const GROUP_SIZE := 64
const STRIDE := 8
const SHADER := preload("res://src/view/city_life/city_life_headlights.gdshader")
var groups: Array[MultiMeshInstance2D] = []
var textures: Array[Texture2DArray] = []
var buffers: Array[PackedFloat32Array] = []
var parameters: Array[PackedFloat32Array] = []
var parameter_textures: Array[ImageTexture] = []
var images: Array[Image] = []
var slots: Dictionary[int, int] = {}
var free_slots: Array[int] = []
var night := 0.0
var raster_scale := 1
var previous_world: Dictionary[int, Vector2] = {}
var _pending_images: Dictionary[int, Image] = {}
var _pending_upload := false
var _pending_frame := -1
var _published := false
var _offset := Vector2i.ZERO


func set_interpolation(value: float) -> void:
	if _pending_upload and Engine.get_process_frames() != _pending_frame:
		_flush_uploads()
	# While the new body batch starts at its previous positions, the old
	# headlight batch must finish there, not restart its previous movement.
	var fraction := 1.0 if _pending_upload else value
	for group in groups:
		(group.material as ShaderMaterial).set_shader_parameter("interpolation", fraction)


func set_night(value: float) -> void:
	night = value
	for group in groups:
		(group.material as ShaderMaterial).set_shader_parameter("night", night)


func render(city: CityState, figures: Array, lights: CityLifeLights, offset: Vector2i, lookup: Callable, prepared: Dictionary = {}, defer_upload := false) -> void:
	if _pending_upload:
		_flush_uploads()
	var can_defer := defer_upload and _published and offset == _offset
	_offset = offset
	var seen: Dictionary[int, bool] = {}
	for figure: CityLifeController.Figure in figures:
		if not figure.walking:
			seen[figure.id] = true
	for id in slots.keys():
		if not seen.has(id):
			var slot := slots[id]
			slots.erase(id)
			previous_world.erase(id)
			free_slots.append(slot)
			images[slot] = null
			var group := slot / GROUP_SIZE
			var at := (slot % GROUP_SIZE) * STRIDE
			buffers[group][at] = 0.0
			buffers[group][at + 5] = 0.0
	var grouped: Array[Array] = []
	for figure: CityLifeController.Figure in figures:
		if figure.walking:
			continue
		if not slots.has(figure.id):
			if free_slots.is_empty():
				_add_group()
			slots[figure.id] = free_slots.pop_back()
		var group := slots[figure.id] / GROUP_SIZE
		while grouped.size() <= group:
			grouped.append([])
		grouped[group].append(figure)
	for group in grouped.size():
		var transforms := buffers[group]
		var values := parameters[group]
		for figure: CityLifeController.Figure in grouped[group]:
			var surface: Dictionary = prepared[figure.id] if prepared.has(figure.id) else lights.surface(city, figure.tile, figure.enter, figure.direction, lookup, false)
			var slot := slots[figure.id]
			var layer := slot % GROUP_SIZE
			if images[slot] != surface.image:
				_pending_images[slot] = surface.image
			var at := layer * STRIDE
			var crop: Rect2i = surface.draw_rect
			var point := Vector2(surface.origin - offset) + Vector2(crop.position) / raster_scale
			var world := lights.cached_vehicle_world(city, figure)
			# Keep world coordinates in a full-precision texture: Compatibility
			# rendering can reduce instance custom data precision.
			transforms[at] = float(crop.size.x) / (96 * raster_scale)
			transforms[at + 3] = point.x
			transforms[at + 5] = float(crop.size.y) / (96 * raster_scale)
			transforms[at + 7] = point.y
			values[layer * 4] = world.x
			values[layer * 4 + 1] = world.y
			values[layer * 4 + 2] = figure.direction + figure.vehicle_kind * 8
			values[layer * 4 + 3] = figure.opacity()
			var delta: Vector2 = previous_world.get(figure.id, world) - world
			values[GROUP_SIZE * 4 + layer * 4] = delta.x
			values[GROUP_SIZE * 4 + layer * 4 + 1] = delta.y
			values[GROUP_SIZE * 4 + layer * 4 + 2] = surface.world_origin.x
			values[GROUP_SIZE * 4 + layer * 4 + 3] = surface.world_origin.y
			values[GROUP_SIZE * 8 + layer * 4] = float(crop.position.x) / (96 * raster_scale)
			values[GROUP_SIZE * 8 + layer * 4 + 1] = float(crop.position.y) / (96 * raster_scale)
			values[GROUP_SIZE * 8 + layer * 4 + 2] = float(crop.size.x) / (96 * raster_scale)
			values[GROUP_SIZE * 8 + layer * 4 + 3] = float(crop.size.y) / (96 * raster_scale)
			previous_world[figure.id] = world
		buffers[group] = transforms
		parameters[group] = values
	_pending_upload = true
	_pending_frame = Engine.get_process_frames()
	if not can_defer:
		_flush_uploads()


func _flush_uploads() -> void:
	# Publish the complete batch together. The next presentation frame has no
	# body-buffer rebuild, leaving room for these receiver texture transfers.
	for slot: int in _pending_images:
		textures[slot / GROUP_SIZE].update_layer(_pending_images[slot], slot % GROUP_SIZE)
		images[slot] = _pending_images[slot]
	_pending_images.clear()
	for index in groups.size():
		groups[index].multimesh.buffer = buffers[index]
		parameter_textures[index].update(Image.create_from_data(GROUP_SIZE, 3, false, Image.FORMAT_RGBAF, parameters[index].to_byte_array()))
	_pending_upload = false
	_published = true


func _add_group() -> void:
	var blank := Image.create(96 * raster_scale, 96 * raster_scale, false, Image.FORMAT_RGBA8 if raster_scale > 1 else Image.FORMAT_RGBAF)
	var layers: Array[Image] = []
	layers.resize(GROUP_SIZE)
	layers.fill(blank)
	var texture := Texture2DArray.new()
	texture.create_from_images(layers)
	var geometry := QuadMesh.new()
	geometry.size = Vector2(96, 96)
	geometry.center_offset = Vector3(48, 48, 0)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.mesh = geometry
	multi.instance_count = GROUP_SIZE
	var shader := ShaderMaterial.new()
	shader.shader = SHADER
	shader.set_shader_parameter("surfaces", texture)
	shader.set_shader_parameter("night", night)
	shader.set_shader_parameter("encoded_surfaces", raster_scale > 1)
	var values := PackedFloat32Array()
	values.resize(GROUP_SIZE * 12)
	var parameter_texture := ImageTexture.create_from_image(Image.create_from_data(GROUP_SIZE, 3, false, Image.FORMAT_RGBAF, values.to_byte_array()))
	shader.set_shader_parameter("headlight_data", parameter_texture)
	var group := MultiMeshInstance2D.new()
	group.multimesh = multi
	group.material = shader
	add_child(group)
	var buffer := PackedFloat32Array()
	buffer.resize(GROUP_SIZE * STRIDE)
	buffer.fill(0.0)
	multi.buffer = buffer
	var start := images.size()
	images.resize(start + GROUP_SIZE)
	for slot in range(start + GROUP_SIZE - 1, start - 1, -1):
		free_slots.append(slot)
	groups.append(group)
	textures.append(texture)
	buffers.append(buffer)
	parameters.append(values)
	parameter_textures.append(parameter_texture)
