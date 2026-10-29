extends SceneTree
## Gestures share the existing camera, and touch never builds during a drag.

var map: CityMapControl
var completed: Array = []
var dabs: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(800, 600)
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	map = CityMapControl.new()
	map.size = Vector2(800, 600)
	root.add_child(map)
	map.set_city_view(CityState.from_document(EmptyCityTemplate.create()), CityMapSource.whole(
		ImageTexture.create_from_image(Image.create_empty(4000, 3000, false, Image.FORMAT_RGBA8))))
	map.selection_completed.connect(func(a: Vector2i, b: Vector2i, path: Array[Vector2i], dragged: bool) -> void:
		completed.append([a, b, path, dragged]))
	map.selection_changed.connect(func(_a: Vector2i, _b: Vector2i, _p: Array[Vector2i], _d: bool) -> void:
		dabs.append(true))
	_reset()
	_test_trackpad()
	_test_pinch()
	_test_scroll_fallback()
	assert(not NativePlatform.attach_pointer_source(0))
	NativePlatform.detach_pointer_source(0)
	assert(not NativePlatform.take_touchpad_scroll(0, 1, 1.0))
	_test_touch()
	await _test_routing()
	map.queue_free()
	await process_frame
	print("PASS: trackpad, wheel fallback, touch navigation, tool isolation, and GUI routing")
	quit()


func _reset() -> void:
	map.navigation.allowed = Callable()
	map.navigation.reset()
	map.zoom_factor = 1.0
	map.source_center = Vector2(2000, 1500)
	map.set_edit_enabled(false)
	map.photo_mode_active = false
	map.map_pixel_ratio = 1.0
	map.screen_pixel_scale = 0.0
	completed.clear()
	dabs.clear()


func _test_trackpad() -> void:
	var pan := InputEventPanGesture.new()
	pan.position = Vector2(400, 300)
	pan.delta = Vector2(0.5, -0.25)
	var before := map.source_center
	assert(map.navigation.handle(pan))
	assert(map.source_center.is_equal_approx(before + pan.delta * CityMapNavigation.PAN_STEP))
	# Map pixel density and zoom are each applied once.
	map.map_pixel_ratio = 2.0
	map.zoom_factor = 2.0
	before = map.source_center
	map.navigation.handle(pan)
	assert(map.source_center.is_equal_approx(before + pan.delta * CityMapNavigation.PAN_STEP / 2.0))
	_reset()
	map.photo_mode_active = true
	map.navigation.handle(pan)
	assert(map.source_center != Vector2(2000, 1500), "Navigation works in read-only and photo views")
	map.navigation.allowed = func() -> bool: return false
	before = map.source_center
	assert(not map.navigation.handle(pan) and map.source_center == before)
	map.navigation.process()
	assert(not map.navigation.active())
	_reset()
	pan.delta = Vector2(1e6, 1e6)
	map.navigation.handle(pan)
	var state := map.camera.scroll_state()
	assert(state.value.x <= state.content.x - state.page.x)
	assert(state.value.y <= state.content.y - state.page.y)


func _test_pinch() -> void:
	_reset()
	var nav := map.navigation
	var point := Vector2(550, 220)
	var source := (point - map.camera._draw_offset(map.camera._view_scale())) / map.camera._view_scale()
	nav._magnify(1.09, point, 1000)
	assert(map.zoom_factor == 1.0)
	nav._magnify(1.09, point, 1010)
	assert(map.zoom_factor == 2.0, "Successive pinch factors multiply")
	var anchored := (point - map.camera._draw_offset(map.camera._view_scale())) / map.camera._view_scale()
	assert(anchored.distance_to(source) < 1.0, "Pinch keeps the source point under its anchor")
	nav._magnify(1.4, point, 1020)
	assert(map.zoom_factor == 2.0, "Pinch limits rapid cache-changing zoom steps")
	nav._magnify(1.0, point, 1200)
	assert(map.zoom_factor == 2.0, "A stationary or ending gesture does not drain pending zoom")
	nav._magnify(1.01, point, 1210)
	assert(map.zoom_factor == 3.0, "A blocked step is retained until new input")
	var zoom := map.zoom_factor
	nav.process()
	assert(map.zoom_factor == zoom, "No timer drains accumulated zoom")
	nav._magnify(1.01, point, 2000)
	assert(map.zoom_factor == zoom, "A new gesture discards the previous remainder")
	nav.reset()
	map.zoom_factor = 4.0
	nav._magnify(2.0, point, 3000)
	nav._magnify(1.0 / 1.2, point, 3200)
	assert(map.zoom_factor == 3.0, "Zoom-limit overshoot does not delay reversal")
	nav._magnify(0.0, point, 3500)
	nav._magnify(NAN, point, 3500)
	assert(map.zoom_factor == 3.0)
	map.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(not nav.active())
	# Pinch stepping must not share the physical wheel's debounce state.
	map.camera._next_wheel_zoom_msec = 999999
	nav._magnify(1.2, point, 4000)
	assert(map.zoom_factor == 4.0)
	map.camera._next_wheel_zoom_msec = 0


func _wheel(button: MouseButton, factor := 1.0, ctrl := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = Vector2(400, 300)
	event.button_index = button
	event.pressed = true
	event.factor = factor
	event.ctrl_pressed = ctrl
	return event


func _touchpad_wheel(button: MouseButton, factor := 1.0) -> InputEventMouseButton:
	var event := _wheel(button, factor)
	event.device = CityMapNavigation.TOUCHPAD_DEVICE
	return event


func _test_scroll_fallback() -> void:
	_reset()
	var wheel := _wheel(MOUSE_BUTTON_WHEEL_UP)
	assert(not map.navigation.handle(wheel), "Default wheel events retain player bindings")
	map.interaction._gui_input(wheel)
	assert(map.zoom_factor == 2.0)
	_reset()
	var before := map.source_center
	assert(not map.navigation.handle(_wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.25)), "High-resolution mice are not mistaken for touchpads")
	assert(map.navigation.handle(_touchpad_wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.25)))
	assert(map.source_center.is_equal_approx(before + Vector2(0, 12)))
	map.navigation.handle(_touchpad_wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.5))
	assert(map.source_center.is_equal_approx(before + Vector2(24, 12)))
	var shifted := _touchpad_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	shifted.shift_pressed = true
	map.navigation.handle(shifted)
	assert(map.source_center.is_equal_approx(before + Vector2(72, 12)))
	map.navigation.handle(_wheel(MOUSE_BUTTON_WHEEL_UP, 0.5, true))
	assert(map.zoom_factor == 1.0)
	map.navigation.handle(_wheel(MOUSE_BUTTON_WHEEL_UP, 0.6, true))
	assert(map.zoom_factor == 2.0, "Fractional Ctrl+wheel supports driver-emulated pinch")


func _touch(index: int, position: Vector2, pressed: bool, canceled := false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	return event


func _contact(index: int, position: Vector2, pressed: bool, canceled := false) -> void:
	var event := _touch(index, position, pressed, canceled)
	map.interaction._input(event)
	map.interaction._gui_input(event)


func _drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	map.interaction._gui_input(event)


func _test_touch() -> void:
	_reset()
	map.set_edit_enabled(true)
	# Center on a real tile so the touch addresses an editable tile.
	map.center_on_tile(Vector2i(64, 64))
	var point := Vector2(400, 300)
	assert(map.camera._tile_at(point).x >= 0)
	_contact(7, point, true)
	assert(dabs.is_empty() and completed.is_empty(), "Touch press cannot build")
	_contact(7, point, false)
	assert(completed.size() == 1, "A single tap uses the tool once on release")
	completed.clear()
	dabs.clear()
	_contact(7, point, true)
	var before := map.source_center
	_drag(7, point + Vector2(60, 20))
	_contact(7, point + Vector2(60, 20), false)
	assert(map.source_center.is_equal_approx(before - Vector2(60, 20)))
	assert(completed.is_empty() and dabs.is_empty(), "One-finger navigation cannot start a stroke")
	_contact(7, point - Vector2(60, 0), true)
	_contact(42, point + Vector2(60, 0), true)
	before = map.source_center
	_drag(7, point - Vector2(20, 0))
	_drag(42, point + Vector2(100, 0))
	map.navigation.process()
	assert(map.zoom_factor == 1.0, "Parallel fingers pan without a transient false pinch")
	assert(map.source_center.is_equal_approx(before - Vector2(40, 0)))
	_drag(7, point - Vector2(50, 0))
	_drag(42, point + Vector2(130, 0))
	map.navigation.process()
	assert(map.zoom_factor == 2.0, "Two-finger span controls fixed zoom levels")
	_contact(42, point + Vector2(130, 0), false)
	_contact(7, point - Vector2(50, 0), false)
	assert(completed.is_empty() and dabs.is_empty(), "Lifting fingers in either order cannot place a tool")
	_contact(9, point, true)
	_contact(9, point, false, true)
	_contact(9, point, false)
	assert(completed.is_empty(), "Canceled contacts cannot later become taps")
	_contact(9, point, true)
	map.interaction._input(_touch(11, Vector2(5, 5), true))
	_contact(9, point, false)
	assert(completed.is_empty(), "A second finger over UI also cancels the tool tap")
	map.navigation.reset()
	var emulated := _wheel(MOUSE_BUTTON_LEFT)
	emulated.device = -1
	map.interaction._gui_input(emulated)
	assert(dabs.is_empty() and not map.is_left_drag_active(), "Touch-emulated mouse cannot duplicate tools")
	_contact(9, point, true)
	map.set_city_view(CityState.from_document(EmptyCityTemplate.create()), map.city_source)
	assert(map.navigation.active(), "A refreshed rendering snapshot must not interrupt navigation")
	# The city session owns the actual document-switch reset.
	map.navigation.reset()
	_contact(9, point, false)
	assert(completed.is_empty(), "Context resets discard pending taps")


func _test_routing() -> void:
	_reset()
	var overlay := Panel.new()
	overlay.position = Vector2(300, 200)
	overlay.size = Vector2(200, 200)
	root.add_child(overlay)
	await process_frame
	var pan := InputEventPanGesture.new()
	pan.position = Vector2(400, 300)
	pan.delta = Vector2(1, 1)
	var before := map.source_center
	root.push_input(pan, true)
	root.push_input(_touch(0, Vector2(400, 300), true), true)
	root.push_input(_touch(0, Vector2(450, 300), false), true)
	assert(map.source_center == before and not map.navigation.active(), "Overlay receives gestures and touch instead of the map")
	root.remove_child(overlay)
	overlay.queue_free()
	await process_frame
	root.push_input(pan, true)
	assert(map.source_center != before, "Viewport routes gestures to the uncovered map")
	before = map.source_center
	root.push_input(_touchpad_wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.25), true)
	assert(map.source_center.is_equal_approx(before + Vector2(0, 12)), "Touchpad identity survives GUI coordinate transforms")
	map.navigation.reset()
	# Input.parse_input_event includes Godot's real touch-to-mouse emulation.
	map.set_edit_enabled(true)
	map.center_on_tile(Vector2i(64, 64))
	completed.clear()
	Input.parse_input_event(_touch(0, Vector2(400, 300), true))
	await process_frame
	assert(completed.is_empty() and not map.is_left_drag_active())
	Input.parse_input_event(_touch(0, Vector2(400, 300), false))
	await process_frame
	assert(completed.size() == 1, "Native emulation path produces exactly one tool tap")
