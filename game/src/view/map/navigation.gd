class_name CityMapNavigation
extends RefCounted
## One finger uses the current tool; two fingers pan and pinch the camera.
## Delay a stationary press briefly so a second contact can start navigation.

const PAN_STEP := 48.0
const PINCH_STEP := 1.18
const PINCH_INTERVAL_MSEC := 140
const GESTURE_IDLE_MSEC := 250
const TAP_SLOP := 12.0
const TOOL_HOLD_MSEC := 180
const TOUCHPAD_DEVICE := 0x5253

var map: CityMapControl
var allowed := Callable()
var _window_handle := 0
var _touches: Dictionary[int, Vector2] = {}
var _screen_touches: Dictionary[int, bool] = {}
var _touch_start := Vector2.ZERO
var _touch_moved := false
var _tool_held := false
var _touch_started_msec := 0
var _multiple := false
var _touch_dirty := false
var _center := Vector2.ZERO
var _span := 0.0
var _pinch_log := 0.0
var _last_pinch_msec := -GESTURE_IDLE_MSEC
var _next_pinch_msec := 0
var _last_navigation_msec := -GESTURE_IDLE_MSEC


func _init(control: CityMapControl) -> void:
	map = control


func attach_window() -> void:
	if OS.get_name() == "Windows" and DisplayServer.get_name() != "headless":
		var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, map.get_window().get_window_id())
		if NativePlatform.attach_pointer_source(handle):
			_window_handle = handle


func detach_window() -> void:
	if _window_handle != 0:
		NativePlatform.detach_pointer_source(_window_handle)
		_window_handle = 0
	reset()


func available() -> bool:
	return map.city_source != null and (not allowed.is_valid() or allowed.call())


func active() -> bool:
	return (not _touches.is_empty()
		or Time.get_ticks_msec() - _last_navigation_msec < GESTURE_IDLE_MSEC)


func is_panning() -> bool:
	return (_multiple and not _touches.is_empty()
		or Time.get_ticks_msec() - _last_navigation_msec < GESTURE_IDLE_MSEC)


func reset() -> void:
	if _tool_held:
		_cancel_tool()
	_tool_held = false
	_touches.clear()
	_screen_touches.clear()
	_touch_dirty = false
	_touch_moved = false
	_multiple = false
	_pinch_log = 0.0
	_span = 0.0
	_next_pinch_msec = 0
	_last_pinch_msec = -GESTURE_IDLE_MSEC
	_last_navigation_msec = -GESTURE_IDLE_MSEC


func observe(event: InputEvent) -> void:
	classify_scroll(event)
	# Observe contacts without consuming UI input. A second finger over a UI
	# panel must also disqualify the first map contact from becoming a tool tap.
	if event is InputEventScreenTouch:
		if event.pressed:
			_screen_touches[event.index] = true
			if not _touches.is_empty() and _screen_touches.size() > 1:
				_multiple = true
				_cancel_touch_tool()
		else:
			_screen_touches.erase(event.index)


func classify_scroll(event: InputEvent) -> void:
	if _window_handle == 0 or not event is InputEventMouseButton or not event.pressed:
		return
	if event.has_meta(&"rs_scroll_source"):
		return
	var axis := 0
	var direction := 1
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			axis = 1
		MOUSE_BUTTON_WHEEL_DOWN:
			axis = 1
			direction = -1
		MOUSE_BUTTON_WHEEL_LEFT:
			direction = -1
		MOUSE_BUTTON_WHEEL_RIGHT:
			pass
		_:
			return
	event.set_meta(&"rs_scroll_source", true)
	if NativePlatform.take_touchpad_scroll(_window_handle, axis, direction * event.factor):
		# Device survives Viewport's coordinate-transformed event copy. Do not
		# infer a touchpad from fractional steps: real mice can send those too.
		event.device = TOUCHPAD_DEVICE


func process() -> void:
	if not active() and _screen_touches.is_empty() and not _touch_dirty:
		return
	if not available():
		if active():
			_cancel_tool()
		reset()
		return
	# Native touch points arrive separately. Sample the pair once per frame so
	# a parallel two-finger swipe does not momentarily look like a pinch.
	if _touch_dirty:
		_flush_touch()
	if not _multiple and _touches.size() == 1 and not _tool_held and Time.get_ticks_msec() - _touch_started_msec >= TOOL_HOLD_MSEC:
		_start_touch_tool()


func handle(event: InputEvent) -> bool:
	# Godot can dispatch this emulated mouse event before the original touch.
	# Filter it at the map, not globally: UI buttons keep normal touch support.
	if event is InputEventMouse and event.device == -1:
		return true
	if not available():
		return false
	if event is InputEventScreenTouch:
		_touch(event)
		return true
	if event is InputEventScreenDrag:
		_drag(event)
		return true
	if event is InputEventPanGesture:
		if _touches.is_empty():
			_begin_navigation()
			if event.ctrl_pressed or event.meta_pressed:
				_magnify(pow(PINCH_STEP, -event.delta.y), event.position)
			else:
				map.camera.pan_screen(event.delta * PAN_STEP * map.map_pixel_ratio)
		return true
	if event is InputEventMagnifyGesture:
		if _touches.is_empty():
			_begin_navigation()
			_magnify(event.factor, event.position)
		return true
	if event is InputEventMouseButton and _wheel(event):
		return true
	return false


func _cancel_tool() -> void:
	map.selection.cancel_active_selection()
	map.interaction.panning = false
	map.interaction._pan_button = MOUSE_BUTTON_NONE
	map.interaction._click_button = MOUSE_BUTTON_NONE
	map.interaction._query_on_release = false
	map.interaction._brush_elapsed = 0.0


func _begin_navigation() -> void:
	_cancel_tool()
	_last_navigation_msec = Time.get_ticks_msec()


func _magnify(factor: float, point: Vector2, now := -1) -> void:
	if not is_finite(factor) or factor <= 0.0 or is_equal_approx(factor, 1.0):
		return
	if now < 0:
		now = Time.get_ticks_msec()
	if now - _last_pinch_msec >= GESTURE_IDLE_MSEC:
		_pinch_log = 0.0
		_next_pinch_msec = 0
	_last_pinch_msec = now
	var step := log(PINCH_STEP)
	_pinch_log = clampf(_pinch_log + log(factor), -step * 2.0, step * 2.0)
	if absf(_pinch_log) + 0.000001 < step or now < _next_pinch_msec:
		return
	var direction := 1 if _pinch_log > 0.0 else -1
	var changed := map.camera.zoom_in(point) if direction > 0 else map.camera.zoom_out(point)
	# At a zoom limit discard the excess, so reversing works immediately.
	_pinch_log = _pinch_log - direction * step if changed else 0.0
	_next_pinch_msec = now + PINCH_INTERVAL_MSEC
	# No timer drains the remainder: a step always needs a new input event.


func _wheel(event: InputEventMouseButton) -> bool:
	var direction := Vector2.ZERO
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			direction.y = -1.0
		MOUSE_BUTTON_WHEEL_DOWN:
			direction.y = 1.0
		MOUSE_BUTTON_WHEEL_LEFT:
			direction.x = -1.0
		MOUSE_BUTTON_WHEEL_RIGHT:
			direction.x = 1.0
		_:
			return false
	var zoom_modifier := event.ctrl_pressed or event.meta_pressed
	if event.device != TOUCHPAD_DEVICE and not zoom_modifier:
		return false
	if not event.pressed:
		return true
	_begin_navigation()
	if zoom_modifier:
		# Windows touchpad pinches commonly arrive as Ctrl+wheel. Preserve the
		# fractional factor instead of treating every packet as a full step.
		_magnify(pow(PINCH_STEP, -direction.y * event.factor), event.position)
	else:
		if event.shift_pressed and direction.x == 0.0:
			direction = Vector2(direction.y, 0.0)
		map.camera.pan_screen(direction * event.factor * PAN_STEP * map.map_pixel_ratio)
	return true


func _touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touches.is_empty():
			_touch_start = event.position
			_touch_moved = false
			_multiple = false
			_touch_started_msec = Time.get_ticks_msec()
			_cancel_tool()
		_touches[event.index] = event.position
		_multiple = _multiple or _touches.size() > 1 or _screen_touches.size() > 1
		if _multiple:
			_cancel_touch_tool()
			_begin_navigation()
		_rebase_touch()
		return
	if not _touches.has(event.index):
		return
	if event.canceled:
		# A canceled point invalidates the whole sequence, including a remaining
		# finger. Its later release must not turn into a tap.
		reset()
		return
	_touches[event.index] = event.position
	_touch_dirty = true
	_flush_touch()
	if not _multiple and _touches.size() == 1 and Rect2(Vector2.ZERO, map.size).has_point(event.position):
		if not _tool_held:
			_start_touch_tool()
		if _tool_held:
			_touch_button(event.position, false)
	elif _tool_held:
		_cancel_touch_tool()
	_tool_held = false
	_touches.erase(event.index)
	_rebase_touch()


func _touch_button(point: Vector2, pressed: bool) -> void:
	var button := InputEventMouseButton.new()
	button.position = point
	button.button_index = MOUSE_BUTTON_LEFT
	button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	button.pressed = pressed
	map.interaction._handle_mouse_button(button)


func _start_touch_tool() -> void:
	if _multiple or _touches.size() != 1 or not available():
		return
	_tool_held = true
	_touch_button(_touch_start, true)


func _cancel_touch_tool() -> void:
	if _tool_held:
		_cancel_tool()
	_tool_held = false


func _drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	_touch_dirty = true
	if _touches.size() == 1:
		_flush_touch()


func _rebase_touch() -> void:
	_touch_dirty = false
	_pinch_log = 0.0
	_next_pinch_msec = 0
	if _touches.is_empty():
		return
	_center = _touch_center()
	_span = _touch_span()


func _touch_center() -> Vector2:
	var center := Vector2.ZERO
	for point: Vector2 in _touches.values():
		center += point
	return center / _touches.size()


func _touch_span() -> float:
	if _touches.size() != 2:
		return 0.0
	var points := _touches.values()
	return (points[0] as Vector2).distance_to(points[1])


func _flush_touch() -> void:
	_touch_dirty = false
	if _touches.is_empty():
		return
	var center := _touch_center()
	var span := _touch_span()
	var pixels := maxf(map.screen_pixel_scale, 1.0)
	if center.distance_to(_touch_start) * pixels > TAP_SLOP:
		_touch_moved = true
	if _multiple and _touches.size() >= 2:
		map.camera.pan_screen(_center - center)
		if _touches.size() == 2 and _span > TAP_SLOP and span > TAP_SLOP:
			_magnify(span / _span, center)
		_last_navigation_msec = Time.get_ticks_msec()
	elif not _multiple and _touch_moved:
		if not _tool_held:
			_start_touch_tool()
		if _tool_held:
			var motion := InputEventMouseMotion.new()
			motion.position = center
			motion.relative = center - _center
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			map.interaction._handle_mouse_motion(motion)
	_center = center
	_span = span
