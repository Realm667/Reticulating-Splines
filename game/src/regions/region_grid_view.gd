class_name RegionGridView
extends Control
## One projection and polygon picking for the overview and the sidebar.

signal cell_selected(cell: Vector2i)

var state := {}
var compass := 0
var compact := false
var selected := Vector2i(-1, -1)
var hovered := Vector2i(-1, -1)
var _pressed := Vector2i(-1, -1)
var _press_position := Vector2.ZERO
var _dragged := false


func _init() -> void:
	custom_minimum_size = Vector2(0, 140)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	mouse_exited.connect(func() -> void:
		hovered = Vector2i(-1, -1)
		_pressed = Vector2i(-1, -1)
		queue_redraw())
	resized.connect(queue_redraw)
	theme_changed.connect(queue_redraw)


func configure(value: Dictionary, rotation: int, selection := Vector2i(-1, -1)) -> void:
	if compass != (rotation & 3) or state.get("active") != value.get("active") or state.get("edge") != value.get("edge"):
		_pressed = Vector2i(-1, -1)
	state = value
	compass = rotation & 3
	selected = selection
	queue_redraw()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_FOCUS_EXIT, NOTIFICATION_APPLICATION_FOCUS_OUT] or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_pressed = Vector2i(-1, -1)


func half_size() -> Vector2:
	var edge := maxi(1, int(state.get("edge", 1)))
	var width := maxf(1, minf((size.x - 12) / (edge * 2.0), (size.y - 12) / edge))
	return Vector2(width, width * 0.5)


func cell_center(cell: Vector2i) -> Vector2:
	var middle := (int(state.get("edge", 1)) - 1) * 0.5
	return size * 0.5 + RegionProjection.project(Vector2(cell) - Vector2.ONE * middle, half_size(), compass)


func polygon(cell: Vector2i) -> PackedVector2Array:
	var center := cell_center(cell)
	var half := half_size() * 0.94
	return PackedVector2Array([center + Vector2(0, -half.y), center + Vector2(half.x, 0),
		center + Vector2(0, half.y), center + Vector2(-half.x, 0)])


func pick(point: Vector2) -> Vector2i:
	for y in int(state.get("edge", 0)):
		for x in int(state.get("edge", 0)):
			var cell := Vector2i(x, y)
			if state.get("occupied_only", false) and item(cell).is_empty():
				continue
			if Geometry2D.is_point_in_polygon(point, polygon(cell)):
				return cell
	return Vector2i(-1, -1)


func item(cell: Vector2i) -> Dictionary:
	for entry: Dictionary in state.get("cells", []):
		if entry.get("cell") == [cell.x, cell.y]:
			return entry
	return {}


func _get_tooltip(at_position: Vector2) -> String:
	var cell := pick(at_position)
	if cell.x < 0:
		return ""
	var entry := item(cell)
	var text := str(entry.get("name", tr("Unowned city area")))
	if entry.has("population"):
		text += "\n" + tr("Population: %d") % int(entry.population)
	if entry.has("player"):
		text += "\n" + str(entry.player) + " · " + MultiplayerSeatWindow.status(entry.status)
	return text


func _gui_input(event: InputEvent) -> void:
	if state.is_empty():
		return
	if event is InputEventMouseMotion:
		if _pressed.x >= 0 and event.position.distance_to(_press_position) > 12:
			_dragged = true
		hovered = pick(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := pick(event.position)
		if event.pressed and cell.x >= 0:
			_pressed = cell
			_press_position = event.position
			_dragged = false
			selected = cell
			grab_focus()
			queue_redraw()
			accept_event()
		elif not event.pressed:
			var pressed := _pressed
			_pressed = Vector2i(-1, -1)
			if pressed.x >= 0:
				if cell == pressed and not _dragged and event.position.distance_to(_press_position) <= 12:
					cell_selected.emit(cell)
				accept_event()
	elif event is InputEventKey and event.pressed:
		var delta := Vector2i.ZERO
		match event.keycode:
			KEY_LEFT: delta = Vector2i(-1, 0)
			KEY_RIGHT: delta = Vector2i(1, 0)
			KEY_UP: delta = Vector2i(0, -1)
			KEY_DOWN: delta = Vector2i(0, 1)
			KEY_ENTER, KEY_SPACE:
				if selected.x >= 0 and (not state.get("occupied_only", false) or not item(selected).is_empty()):
					cell_selected.emit(selected)
			_:
				return
		if delta != Vector2i.ZERO:
			var origin := selected if selected.x >= 0 else Vector2i.ZERO
			var turned := Vector2i(RegionProjection.rotate(Vector2(delta), -compass))
			if state.get("occupied_only", false):
				var closest := INF
				var has_origin := not item(selected).is_empty()
				for entry: Dictionary in state.get("cells", []):
					var candidate := Vector2i(entry.cell[0], entry.cell[1])
					var offset := candidate - origin
					if not has_origin or Vector2(offset).dot(Vector2(turned)) > 0:
						if offset.length_squared() < closest:
							closest = offset.length_squared()
							selected = candidate
			else:
				selected = (origin + turned).clamp(Vector2i.ZERO, Vector2i.ONE * (int(state.edge) - 1))
			queue_redraw()
		accept_event()


func _draw() -> void:
	var ink := get_theme_color("font_color", "Label")
	var green := Color("2c873c") if ink.get_luminance() < 0.5 else Color("8ddb74")
	for y in int(state.get("edge", 0)):
		for x in int(state.get("edge", 0)):
			var cell := Vector2i(x, y)
			var entry := item(cell)
			if state.get("occupied_only", false) and entry.is_empty():
				continue
			var own := bool(entry.get("own", false))
			var color := Color.from_string(str(entry.get("color", "")), green if own else Color(ink, 0.5))
			var active: bool = state.get("active", []) == [x, y]
			var shape := polygon(cell)
			draw_colored_polygon(shape, Color(color, 0.28) if active else Color(ink, 0.07 if entry.is_empty() else 0.14))
			var outline := shape.duplicate()
			outline.append(shape[0])
			draw_polyline(outline, color, 4.0 if active or hovered == cell else 1.5, true)
			if selected == cell and not compact:
				draw_circle(cell_center(cell), 3, ink)
			if not compact and half_size().x > 45:
				var text: String = entry.get("name", "%d,%d" % [x + 1, y + 1])
				var font := get_theme_font("font", "Label")
				var width := half_size().x * 1.5
				var line := TextLine.new()
				line.add_string(text, font, 12)
				line.width = width
				line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				line.alignment = HORIZONTAL_ALIGNMENT_CENTER
				line.draw(get_canvas_item(), cell_center(cell) - Vector2(width * 0.5, line.get_size().y * 0.5), ink)
