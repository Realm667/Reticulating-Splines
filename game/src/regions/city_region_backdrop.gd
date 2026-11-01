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
var job_cell := Vector2i(-1, -1)
var press_cell := Vector2i(-1, -1)
var press_position := Vector2.ZERO


func _init(control: CityMapControl) -> void:
	map = control


func clear() -> void:
	if job != null:
		job.cancel()
		job.join()
		job = null
	textures.clear()
	pending.clear()
	documents.clear()
	state.clear()
	press_cell = Vector2i(-1, -1)
	map.queue_redraw()


func configure(value: Dictionary, source: Dictionary[String, Sc2File], artwork: LoadedAssetState, rotation: int) -> void:
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
	map.camera._on_resized()


func poll() -> void:
	if job != null and job.finished():
		job.join()
		if job.image != null and not job.cancelled():
			textures[job_cell] = ImageTexture.create_from_image(job.image)
		job = null
		map.queue_redraw()
	if job == null and not pending.is_empty() and assets != null:
		job_cell = pending.pop_front()
		job = CityPreviewJob.for_assets(assets)
		job.document = documents[RegionRules.key(job_cell)].duplicate_document(true)
		job.background = Color.TRANSPARENT
		job.desired_compass = compass
		job.maximum_map_size = 4096
		job.grayscale = true
		job.start()


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


func draw_on(canvas: CanvasItem, scale: float, offset: Vector2) -> void:
	if map.city == null or map.city_source == null or map.data_view_mode != CityViewMode.Mode.NONE:
		return
	for cell: Vector2i in textures:
		var texture := textures[cell]
		canvas.draw_texture_rect(texture, Rect2(offset + displacement(cell) * scale,
			Vector2(map.city_source.size) * scale), false, Color(1, 1, 1, 0.5))


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
