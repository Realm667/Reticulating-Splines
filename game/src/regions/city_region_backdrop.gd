class_name CityRegionBackdrop
extends RefCounted
## Bounded static views of owned city areas. No inactive city is simulated here.

var map: CityMapControl
var requested := Callable()
var state := {}
var compass := 0
var textures: Dictionary[Vector2i, Texture2D] = {}
var pending: Array[Vector2i] = []
var documents: Dictionary[String, Sc2File] = {}
var assets: LoadedAssetState
var job: CityPreviewJob
var _retired: Array[CityPreviewJob] = []
var job_cell := Vector2i(-1, -1)
var press_cell := Vector2i(-1, -1)
var press_position := Vector2.ZERO
var layer: Control
var opacity: Dictionary[Vector2i, float] = {}
var hovered := Vector2i(-1, -1)
var live_ready := Callable()
var presentation_state := Callable()
var _snapshot: CityRegionSnapshot
var _capture_queue: Array[Dictionary] = []
var _capture_job := false
var _prepared: Dictionary[Vector2i, Texture2D] = {}
var _switch_target := Vector2i(-1, -1)
var _switch_source := Vector2i(-1, -1)
var _switch_compass := 0
var _switch_callback := Callable()
var _activation_expected := false
var _incoming: Texture2D
var _outgoing := Vector2i(-1, -1)
var _fade_time := -1.0
var _incoming_opacity := 0.66
const REST_OPACITY := 0.33
const HOVER_OPACITY := 0.66
const FADE_SECONDS := 1.0
const SNAPSHOT_SHADER := preload("res://src/regions/region_snapshot.gdshader")


func _init(control: CityMapControl) -> void:
	map = control


func live_opacity() -> float:
	return map.modulate.a


func _set_live_opacity(value: float) -> void:
	# Fade the frozen picture, then reveal the fully prepared live view. A
	# CanvasGroup cannot safely contain screen-reading fog/tilt-shift passes:
	# their backbuffer copies can replace transparent space with raw pixels.
	map.modulate.a = value
	map.visible = value >= 1.0


func clear() -> void:
	if _snapshot != null:
		_snapshot.close()
		_snapshot = null
	if job != null:
		job.cancel()
		_retired.append(job)
		job = null
	_reap_finished()
	textures.clear()
	opacity.clear()
	pending.clear()
	documents.clear()
	state.clear()
	cancel_switch()
	press_cell = Vector2i(-1, -1)
	if is_instance_valid(layer):
		layer.hide()
	map.queue_redraw()


func cancel_switch() -> void:
	if _snapshot != null:
		_snapshot.close()
		_snapshot = null
	_capture_queue.clear()
	_prepared.clear()
	_switch_target = Vector2i(-1, -1)
	_switch_source = Vector2i(-1, -1)
	_switch_callback = Callable()
	_activation_expected = false
	_incoming = null
	_outgoing = Vector2i(-1, -1)
	_fade_time = -1.0
	_set_live_opacity(1.0)


func busy() -> bool:
	return _switch_target.x >= 0 or _fade_time >= 0.0


func close() -> void:
	clear()
	# Tree shutdown owns the final join. Ordinary map switches never wait here.
	for retired in _retired:
		retired.join()
	_retired.clear()
	assets = null
	if is_instance_valid(layer):
		layer.queue_free()
		layer = null


func _reap_finished() -> void:
	for index in range(_retired.size() - 1, -1, -1):
		if _retired[index].finished():
			_retired[index].join()
			_retired.remove_at(index)


static func prioritize(cells: Array[Vector2i], origin: Vector2i) -> void:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var first := a.distance_squared_to(origin)
		var second := b.distance_squared_to(origin)
		return first < second if first != second else a.x < b.x if a.x != b.x else a.y < b.y)


func configure(value: Dictionary, source: Dictionary[String, Sc2File], artwork: LoadedAssetState, rotation: int) -> void:
	var target := _switch_target
	var previous := _switch_source
	var incoming_opacity: float = opacity.get(target, HOVER_OPACITY)
	var preserve: bool = _activation_expected and value.get("active") == [target.x, target.y] and rotation == _switch_compass
	var prepared := _prepared.duplicate() if preserve else {}
	clear()
	state = value
	compass = rotation
	assets = artwork
	for entry: Dictionary in state.get("cells", []):
		var position := Vector2i(int(entry.cell[0]), int(entry.cell[1]))
		var id := RegionRules.key(position)
		if entry.get("own", false) and entry.cell != state.get("active") and source.has(id):
			documents[id] = source[id]
			pending.append(position)
	var active: Array = state.get("active", [0, 0])
	if preserve:
		for cell: Vector2i in prepared:
			if cell != target:
				textures[cell] = prepared[cell]
				opacity[cell] = REST_OPACITY
				pending.erase(cell)
		_incoming = prepared.get(target)
		_outgoing = previous
		_incoming_opacity = incoming_opacity
		_fade_time = 0.0
		_set_live_opacity(0.0)
	prioritize(pending, Vector2i(active[0], active[1]))
	_ensure_layer()
	map.camera._on_resized()
	draw_on(map, 0, Vector2.ZERO)


func _ensure_layer() -> void:
	if is_instance_valid(layer) or map.get_parent() == null:
		return
	# Draw above the live city and below the interface. The incoming still
	# remains visible while the actual city is hidden during preparation.
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.clip_contents = true
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new()
	material.shader = SNAPSHOT_SHADER
	layer.material = material
	layer.draw.connect(_draw_layer)
	var live_canvas: CanvasItem = map.get_parent() if map.get_parent() is Node2D else map
	live_canvas.get_parent().add_child(layer)
	live_canvas.get_parent().move_child(layer, live_canvas.get_index() + 1)


func begin_switch(target: Vector2i, current: Sc2File, target_compass: int, callback: Callable) -> bool:
	if busy() or not textures.has(target) or current == null:
		return false
	if job != null:
		job.cancel()
		_retired.append(job)
		job = null
	_switch_target = target
	var active: Array = state.get("active", [0, 0])
	_switch_source = Vector2i(active[0], active[1])
	_switch_compass = target_compass
	_switch_callback = callback
	_prepared.assign(textures if target_compass == compass else {})
	_capture_queue.append({"cell": _switch_source, "document": current.duplicate_document(true)})
	if not _prepared.has(target):
		if not documents.has(RegionRules.key(target)):
			cancel_switch()
			return false
		_capture_queue.append({"cell": target, "document": documents[RegionRules.key(target)].duplicate_document(true)})
	return true


func poll() -> void:
	_reap_finished()
	if _snapshot != null:
		var image := _snapshot.poll()
		if image == null:
			return
		_publish_image(image)
		_snapshot.close()
		_snapshot = null
	if job != null and job.finished():
		job.join()
		if job.image != null and not job.cancelled():
			if job is CityRegionPreviewJob:
				var values: Dictionary = presentation_state.call() if presentation_state.is_valid() else {}
				_snapshot = CityRegionSnapshot.new()
				_snapshot.begin(map.get_tree().root, job, values.get("options", VisualEnhancementOptions.normalize({})), values.get("atmosphere", {}))
			else:
				_publish_image(job.image)
		elif _capture_job:
			var callback := _switch_callback
			var target := _switch_target
			cancel_switch()
			if callback.is_valid():
				callback.call_deferred(target)
		job = null
		map.queue_redraw()
	if _snapshot != null:
		return
	if job == null and _switch_target.x >= 0 and _capture_queue.is_empty() and not _activation_expected:
		_activation_expected = true
		_switch_callback.call_deferred(_switch_target)
	if job == null and _retired.is_empty() and assets != null and not _activation_expected and (not _capture_queue.is_empty() or (_switch_target.x < 0 and not pending.is_empty())):
		_capture_job = not _capture_queue.is_empty()
		var capture: Dictionary = _capture_queue.pop_front() if _capture_job else {}
		job_cell = capture.cell if _capture_job else pending.pop_front()
		job = CityRegionPreviewJob.create(assets)
		job.document = capture.document if _capture_job else documents[RegionRules.key(job_cell)].duplicate_document(true)
		job.background = Color.TRANSPARENT
		job.desired_compass = _switch_compass if _capture_job else compass
		job.maximum_map_size = 4096
		job.start()


func _publish_image(image: Image) -> void:
	var texture := ImageTexture.create_from_image(image)
	if _capture_job:
		_prepared[job_cell] = texture
	else:
		textures[job_cell] = texture
		opacity[job_cell] = REST_OPACITY
	map.queue_redraw()


func advance(delta: float, pointer_override := Vector2.INF) -> void:
	if map.city == null or map.city_source == null or state.is_empty():
		return
	var pointer := map.get_local_mouse_position() if pointer_override == Vector2.INF else pointer_override
	hovered = pick(pointer) if map.is_visible_in_tree() and map.camera._camera_rect().has_point(pointer) else Vector2i(-1, -1)
	var changed := false
	for cell: Vector2i in textures:
		var target := HOVER_OPACITY if cell == hovered else REST_OPACITY
		var previous: float = opacity.get(cell, REST_OPACITY)
		opacity[cell] = move_toward(previous, target, delta * (HOVER_OPACITY - REST_OPACITY) / FADE_SECONDS)
		changed = changed or not is_equal_approx(previous, opacity[cell])
	if _fade_time >= 0.0 and (not live_ready.is_valid() or live_ready.call()):
		_fade_time = minf(FADE_SECONDS, _fade_time + delta)
		_set_live_opacity(_fade_time / FADE_SECONDS)
		changed = true
		if _fade_time >= FADE_SECONDS:
			_fade_time = -1.0
			_incoming = null
			_outgoing = Vector2i(-1, -1)
	if changed:
		map.queue_redraw()
	if changed or _fade_time >= 0.0:
		draw_on(map, 0, Vector2.ZERO)


func add_document(cell: Vector2i, document: Sc2File) -> void:
	var id := RegionRules.key(cell)
	if documents.has(id):
		return
	documents[id] = document
	pending.append(cell)


func displacement(cell: Vector2i) -> Vector2:
	var active: Array = state.get("active", [0, 0])
	var delta := Vector2(cell) - Vector2(active[0], active[1])
	return RegionProjection.project(delta * (map.city.map_size + 8),
		Vector2(CityIsometricRenderer.HALF_WIDTH, CityIsometricRenderer.HALF_HEIGHT), compass)


func polygon(cell: Vector2i) -> PackedVector2Array:
	var edge := map.city.map_size
	var half := Vector2(CityIsometricRenderer.HALF_WIDTH, CityIsometricRenderer.HALF_HEIGHT) * edge
	var center := displacement(cell) + Vector2(CityIsometricRenderer.SIDE_MARGIN + half.x,
		CityIsometricRenderer.TOP_MARGIN + half.y)
	return PackedVector2Array([center + Vector2(0, -half.y), center + Vector2(half.x, 0),
		center + Vector2(0, half.y), center + Vector2(-half.x, 0)])


func source_bounds() -> Rect2:
	var result := Rect2(Vector2.ZERO, Vector2(map.city_source.size))
	for cell: Vector2i in textures:
		result = result.merge(Rect2(displacement(cell), Vector2(map.city_source.size)))
	return result


func draw_on(_canvas: CanvasItem, _scale: float, _offset: Vector2) -> void:
	if state.is_empty():
		if is_instance_valid(layer):
			layer.hide()
		return
	_ensure_layer()
	if not is_instance_valid(layer):
		return
	layer.position = map.position
	layer.size = map.size
	var parent := map.get_parent() as CanvasItem
	layer.visible = (parent == null or parent.is_visible_in_tree()) and map.city != null and map.city_source != null and map.data_view_mode == CityViewMode.Mode.NONE
	layer.queue_redraw()


func _draw_layer() -> void:
	if map.city_source == null:
		return
	var scale := map.camera._view_scale()
	var offset := map.camera._draw_offset(scale)
	for cell: Vector2i in textures:
		var texture := textures[cell]
		var fade := _fade_time / FADE_SECONDS if cell == _outgoing and _fade_time >= 0.0 else 1.0
		var alpha: float = lerpf(1.0, REST_OPACITY, fade) if cell == _outgoing and _fade_time >= 0.0 else opacity.get(cell, REST_OPACITY)
		layer.draw_texture_rect(texture, Rect2(offset + displacement(cell) * scale,
			Vector2(map.city_source.size) * scale), false, Color(fade, fade, 0, alpha))
	if _incoming != null and _fade_time >= 0.0:
		var fade := _fade_time / FADE_SECONDS
		layer.draw_texture_rect(_incoming, Rect2(offset, Vector2(map.city_source.size) * scale), false,
			Color(1.0 - fade, 1.0 - fade, 0, lerpf(_incoming_opacity, 1.0, fade)))


func pick(local_point: Vector2) -> Vector2i:
	if map.city == null or map.city_source == null or map.data_view_mode != CityViewMode.Mode.NONE:
		return Vector2i(-1, -1)
	# Never intercept a tool on the active city's visible terrain or buildings.
	if map.camera._tile_at(local_point).x >= 0:
		return Vector2i(-1, -1)
	var scale := map.camera._view_scale()
	var source := (local_point - map.camera._draw_offset(scale)) / scale
	for cell: Vector2i in textures:
		if Geometry2D.is_point_in_polygon(source, polygon(cell)):
			return cell
	return Vector2i(-1, -1)


func handle_button(event: InputEventMouseButton) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT or map.selection_start.x >= 0 or map.photo_mode_active:
		return false
	if event.pressed:
		press_cell = pick(event.position)
		press_position = event.position
		return press_cell.x >= 0
	if press_cell.x < 0:
		return false
	var target := press_cell
	press_cell = Vector2i(-1, -1)
	if target == pick(event.position) and event.position.distance_to(press_position) <= 12 and requested.is_valid():
		requested.call_deferred(target)
	return true
