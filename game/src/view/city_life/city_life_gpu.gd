class_name CityLifeGpu
extends RefCounted
## Persistent source art and cached mask layers; only small instance buffers move.

@warning_ignore_start("integer_division")

const SHADER := preload("res://src/view/city_life/city_life_gpu.gdshader")
const GROUP := 64
const STRIDE := 8
const MASK_LAYERS := 256
const MASK_CAPACITY := MASK_LAYERS * 3
const CELL := Vector2i(32, 16)
var artwork: ImageTexture
var emission: ImageTexture
var rectangles: Dictionary[int, Rect2i] = {}
var groups: Array[MultiMeshInstance2D] = []
var emissions: Array[MultiMeshInstance2D] = []
var buffers: Array[PackedFloat32Array] = []
var data: Array[PackedFloat32Array] = []
var textures: Array[ImageTexture] = []
var masks: Array[Texture2DArray] = []
var identities := PackedInt64Array()
var mask_images: Array = []
var mask_slots: Dictionary[Vector3i, int] = {}
var _next_mask_slot := 0
var cropped: Dictionary[Vector3i, MaskEntry] = {}
var _mask_banks: Dictionary[int, Dictionary] = {}
var _mask_signature: Array = []
var _mask_binding_changed := false
var blank := Image.create(128, 128, false, Image.FORMAT_RGBA8)
var blank_mask := Image.create(128, 128, false, Image.FORMAT_R8)
var blend := 1.0
var origin := Vector2i.ZERO
var upload_bytes := 0
var artwork_scale := 1


func _init() -> void:
	identities.resize(MASK_CAPACITY)


func prepare(sprites: CityLifeSprites, lights: CityLifeLights) -> void:
	if artwork != null:
		return
	artwork_scale = sprites.authored.city_life_scale if sprites.authored != null else 1
	var image := Image.create(1024 * artwork_scale, 512 * artwork_scale, false, Image.FORMAT_RGBA8)
	var lamp_image := Image.create(1024 * artwork_scale, 512 * artwork_scale, false, Image.FORMAT_RGBA8)
	for walking in [false, true]:
		for kind in (1 if walking else 3):
			for variant in (6 if walking else 18):
				for direction in 8:
					for phase in (2 if walking else 1):
						var sprite := sprites.sprite(walking, variant, direction, phase, kind)
						var index := rectangles.size()
						var point := Vector2i(index % 32, index / 32) * CELL * artwork_scale
						var art := _scaled(sprites.master_image(sprite), sprite.get_size() * artwork_scale)
						var rect := Rect2i(point, art.get_size())
						assert(rect.end.y <= image.get_height())
						image.blit_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), point)
						if not walking:
							var light := _scaled(sprites.lamp_image(sprite, lights, kind, direction, true), art.get_size())
							lamp_image.blit_rect(light, Rect2i(Vector2i.ZERO, art.get_size()), point)
						rectangles[sprite.get_instance_id()] = rect
	artwork = ImageTexture.create_from_image(image)
	emission = ImageTexture.create_from_image(lamp_image)


func render(canvas: CityLifeCanvas, entries: Array[Dictionary]) -> void:
	origin = canvas.source_bounds.position
	upload_bytes = 0
	var count := entries.size()
	while groups.size() * GROUP < count:
		add_group(canvas)
	prepare_masks(canvas, entries)
	if _mask_binding_changed:
		for node in groups + emissions:
			if is_instance_valid(node):
				_apply_mask_pages(node.material as ShaderMaterial)
		_mask_binding_changed = false
	var mask_origins := PackedVector2Array()
	var mask_layers := PackedInt32Array()
	for entry in entries:
		var figure: CityLifeController.Figure = entry.figure
		var cached: MaskEntry = cropped[Vector3i(figure.tile.x, figure.tile.y, figure.enter % 2)]
		mask_origins.append(Vector2(cached.origin))
		mask_layers.append(cached.slot)
	var streams := NativeVisualRaster.figure_buffers(entries, rectangles, mask_origins, mask_layers, origin, artwork_scale, GROUP)
	for group in streams.size() / 2:
		buffers[group] = streams[group * 2]
		data[group] = streams[group * 2 + 1]
		data[group].resize(GROUP * 16)
		for slot in mini(GROUP, count - group * GROUP):
			data[group][GROUP * 12 + slot * 4] = entries[group * GROUP + slot].get("shear", 0.0)
	for index in groups.size():
		var visible_count := clampi(count - index * GROUP, 0, GROUP)
		groups[index].multimesh.visible_instance_count = visible_count
		groups[index].visible = visible_count > 0
		if not groups[index].visible:
			continue
		groups[index].multimesh.buffer = buffers[index]
		textures[index].update(Image.create_from_data(GROUP, 4, false, Image.FORMAT_RGBAF, data[index].to_byte_array()))
		upload_bytes += GROUP * (STRIDE + 16) * 4


func prepare_masks(canvas: CityLifeCanvas, entries: Array[Dictionary], budget_usec := 0) -> bool:
	_select_mask_bank(canvas._occlusion_signature)
	var count := entries.size()
	# Mask addresses belong to world tiles, independently of painter-order groups.
	# Reordering moving figures therefore does not upload unchanged silhouettes.
	var live: Dictionary[Vector3i, bool] = {}
	# The complete live set is needed only when a new tile must evict a slot.
	var live_ready := false
	var changed_layers: Dictionary[int, Dictionary] = {}
	var preparation_usec := 0
	var complete := true
	for index in count:
		var started := Time.get_ticks_usec()
		var prepared := false
		var entry := entries[index]
		var figure: CityLifeController.Figure = entry.figure
		var key := Vector3i(figure.tile.x, figure.tile.y, figure.enter % 2)
		var candidates: Array = entry.occluders
		var version: int = candidates[0].image.get_instance_id() if not candidates.is_empty() else 0
		var cached: MaskEntry = cropped.get(key)
		if cached == null:
			if _next_mask_slot >= MASK_CAPACITY and not live_ready:
				for current: Dictionary in entries:
					var occupant: CityLifeController.Figure = current.figure
					live[Vector3i(occupant.tile.x, occupant.tile.y, occupant.enter % 2)] = true
				live_ready = true
			cached = MaskEntry.new()
			cached.slot = _mask_slot(key, live)
			_ensure_mask_page(cached.slot / MASK_LAYERS)
			cropped[key] = cached
		if cached.version != version:
			prepared = true
			var point: Vector2i = canvas._occluder_bounds.get(key, Rect2i(entry.origin, Vector2i.ONE)).position - Vector2i(32, 32)
			cached.version = version
			cached.image = blank_mask
			if not candidates.is_empty():
				var image := blank.duplicate()
				for candidate: Dictionary in candidates:
					image.blend_rect(candidate.image, Rect2i(Vector2i.ZERO, candidate.image.get_size()), candidate.origin - point)
				if not image.is_invisible():
					cached.image = NativeVisualRaster.alpha_mask(image)
			cached.origin = point
			cached.identity = cached.image.get_instance_id()
		var slot := cached.slot
		var identity := cached.identity
		var page := slot / MASK_LAYERS
		var layer := slot % MASK_LAYERS
		if identities[slot] != identity:
			prepared = true
			if not changed_layers.has(page):
				changed_layers[page] = {}
			changed_layers[page][layer] = cached.image
			mask_images[page][layer] = cached.image
			identities[slot] = identity
			upload_bytes += 128 * 128
		if prepared:
			preparation_usec += Time.get_ticks_usec() - started
		if prepared and budget_usec > 0 and preparation_usec >= budget_usec:
			complete = index + 1 == count
			break
	for page: int in changed_layers:
		var changed := changed_layers[page]
		if changed.size() >= GROUP:
			var replacement := Texture2DArray.new()
			var images: Array[Image] = mask_images[page]
			replacement.create_from_images(images)
			masks[page] = replacement
			_mask_binding_changed = true
			upload_bytes += (MASK_LAYERS - changed.size()) * 128 * 128
		else:
			for layer: int in changed:
				masks[page].update_layer(changed[layer], layer)
	return complete


func _select_mask_bank(signature: Array) -> void:
	if signature == _mask_signature:
		return
	# Three artwork sizes, each capped at 768 R8 layers (12 MiB on the GPU).
	# Keep the old draw's bindings until the complete new batch is published.
	if not _mask_signature.is_empty():
		_mask_banks[_mask_signature[3]] = {"signature": _mask_signature, "masks": masks,
			"images": mask_images, "identities": identities, "slots": mask_slots,
			"next": _next_mask_slot, "cropped": cropped}
		if signature[0] != _mask_signature[0]:
			_mask_banks.clear()
	var bank: Dictionary = _mask_banks.get(signature[3], {})
	if not bank.is_empty() and bank.signature == signature:
		masks = bank.masks
		mask_images = bank.images
		identities = bank.identities
		mask_slots = bank.slots
		_next_mask_slot = bank.next
		cropped = bank.cropped
	else:
		masks = []
		mask_images = []
		identities = PackedInt64Array()
		identities.resize(MASK_CAPACITY)
		mask_slots = {}
		_next_mask_slot = 0
		cropped = {}
	_mask_signature = signature
	_mask_binding_changed = true
	_ensure_mask_page(0)


func sync(app: CityApplication, lights: bool, fraction: float) -> void:
	blend = fraction
	for group in groups:
		var shader := group.material as ShaderMaterial
		app.map_view.layers._apply_environment(shader)
		shader.set_shader_parameter("vehicle_has_emission", lights)
		shader.set_shader_parameter("interpolation", blend)
		shader.set_shader_parameter("smooth_movement", bool(app.preferences.visual_enhancements.traffic_vehicles_enabled))
	for copy in emissions:
		(copy.material as ShaderMaterial).set_shader_parameter("interpolation", blend)
		(copy.material as ShaderMaterial).set_shader_parameter("smooth_movement", bool(app.preferences.visual_enhancements.traffic_vehicles_enabled))


func sync_emission(parent: Node2D) -> void:
	parent.position = origin
	if not emissions.is_empty() and not is_instance_valid(emissions[0]):
		emissions.clear()
	while emissions.size() < groups.size():
		var index := emissions.size()
		var copy := MultiMeshInstance2D.new()
		copy.multimesh = groups[index].multimesh
		copy.material = groups[index].material.duplicate()
		(copy.material as ShaderMaterial).set_shader_parameter("emission_only", true)
		parent.add_child(copy)
		emissions.append(copy)
	for index in emissions.size():
		emissions[index].visible = groups[index].visible
		(emissions[index].material as ShaderMaterial).set_shader_parameter("interpolation", blend)


func add_group(parent: Node2D) -> void:
	var geometry := QuadMesh.new()
	geometry.size = Vector2.ONE
	geometry.center_offset = Vector3(0.5, 0.5, 0)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_2D
	mesh.mesh = geometry
	mesh.instance_count = GROUP
	var buffer := PackedFloat32Array()
	buffer.resize(GROUP * STRIDE)
	buffers.append(buffer)
	var values := PackedFloat32Array()
	values.resize(GROUP * 16)
	data.append(values)
	var texture := ImageTexture.create_from_image(Image.create_from_data(GROUP, 4, false, Image.FORMAT_RGBAF, values.to_byte_array()))
	textures.append(texture)
	_ensure_mask_page(0)
	var shader := ShaderMaterial.new()
	shader.shader = SHADER
	shader.set_shader_parameter("artwork", artwork)
	shader.set_shader_parameter("artwork_scale", float(artwork_scale))
	shader.set_shader_parameter("lamps", emission)
	_apply_mask_pages(shader)
	shader.set_shader_parameter("parameters", texture)
	var node := MultiMeshInstance2D.new()
	node.multimesh = mesh
	node.material = shader
	parent.add_child(node)
	groups.append(node)


func _mask_slot(key: Vector3i, live: Dictionary[Vector3i, bool]) -> int:
	if mask_slots.has(key):
		return mask_slots[key]
	var slot := _next_mask_slot
	var fresh := slot < MASK_CAPACITY
	if fresh:
		_next_mask_slot += 1
	else:
		slot = -1
		# At most 600 figure tiles are live; three portable 256-layer pages
		# leave a bounded reserve for motion and recently visited tiles.
		for previous in mask_slots:
			if not live.has(previous):
				slot = mask_slots[previous]
				mask_slots.erase(previous)
				cropped.erase(previous)
				break
		assert(slot >= 0, "Figure mask working set exceeds its fixed capacity")
	mask_slots[key] = slot
	# New pages are already blank. Empty silhouettes need no image upload.
	identities[slot] = blank_mask.get_instance_id() if fresh else 0
	return slot


func _ensure_mask_page(page: int) -> void:
	while masks.size() <= page:
		var layers: Array[Image] = []
		layers.resize(MASK_LAYERS)
		layers.fill(blank_mask)
		mask_images.append(layers)
		var texture := Texture2DArray.new()
		texture.create_from_images(layers)
		masks.append(texture)
		_mask_binding_changed = true


func _apply_mask_pages(shader: ShaderMaterial) -> void:
	for page in 3:
		shader.set_shader_parameter(["masks", "masks_second", "masks_third"][page], masks[mini(page, masks.size() - 1)])


static func _scaled(image: Image, size: Vector2i) -> Image:
	if image.get_size() == size:
		return image
	var result: Image = image.duplicate()
	result.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	return result


class MaskEntry extends RefCounted:
	# World-tile residency survives painter-order changes. Resolve the texture
	# slot and image identity only when that tile's mask actually changes.
	var slot := 0
	var version := -1
	var image: Image
	var origin := Vector2i.ZERO
	var identity := 0
