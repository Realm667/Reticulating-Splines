extends SceneTree

var background_presses := 0
var selected := 0
var toolbar: CityToolbar


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1000, 800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_factor = 1.0
	var host := Control.new()
	host.theme = AppUiTheme.current()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := Button.new()
	host.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.pressed.connect(func() -> void: background_presses += 1)
	toolbar = preload("res://src/ui/shell/city_toolbar.tscn").instantiate()
	host.add_child(toolbar)
	toolbar.group_requested.connect(func(group: int) -> void:
		selected = toolbar.show_tool_group(group, null, Callable(), selected)
		toolbar.sync_child_tool_selection(group, selected))
	toolbar.subtool_requested.connect(func(index: int) -> void:
		selected = index
		toolbar.sync_child_tool_selection(CityToolIds.Group.ROADS, index))
	await process_frame
	await process_frame
	var road_button := toolbar.toolbar_buttons[CityToolIds.Group.ROADS]
	await _click(road_button.get_global_rect().get_center())
	assert(not toolbar.hold_menu.visible, "A single click uses the remembered tool without opening choices")
	toolbar.hold_menu.hide()
	await process_frame
	await _click(road_button.get_global_rect().get_center(), true)
	await process_frame
	await process_frame
	await process_frame
	assert(toolbar.hold_menu.visible)
	var bounds := Rect2i(root.get_visible_rect())
	assert(bounds.encloses(Rect2i(toolbar.hold_menu.position, toolbar.hold_menu.size)))
	var outside := Vector2(bounds.end - Vector2i(20, 20))
	# Real input updates Input's button mask, dismisses the embedded popup, and
	# would press the background button without the toolbar's dismissal guard.
	await _click(outside)
	assert(not toolbar.hold_menu.visible, "Outside click closes the flyout")
	assert(background_presses == 0, "Dismissal must not click the background")
	await _click(outside)
	assert(background_presses == 1, "The next deliberate click must work")
	await _check_hold(road_button, outside)
	for viewport_size in [Vector2i(800, 600), Vector2i(1280, 720)]:
		root.size = viewport_size
		await process_frame
		var view := Rect2i(Vector2i.ZERO, viewport_size)
		for origin in [Vector2.ZERO, Vector2(viewport_size - Vector2i(32, 32)), Vector2(100, 500)]:
			var fitted := CityToolHoldMenu.fit_to_view(Rect2(origin, Vector2(32, 32)), Vector2i(320, 450), view)
			assert(view.encloses(fitted), "Flyouts must stay inside the viewport at each edge")
		toolbar.show_tool_group(CityToolIds.Group.POWER, null)
		toolbar.hold_menu.show_palette(0, Rect2(Vector2(viewport_size - Vector2i(32, 32)), Vector2(32, 32)))
		await process_frame
		await process_frame
		await process_frame
		assert(view.encloses(Rect2i(toolbar.hold_menu.position, toolbar.hold_menu.size)), "The laid-out power menu must fit a small window")
		toolbar.hold_menu.hide()
	var point := toolbar.toolbar_buttons[CityToolIds.Group.ROADS].get_global_rect().get_center()
	await _mouse_button(point, true)
	toolbar.set_landscape_editor(true)
	await create_timer(CityToolbar.HOLD_SECONDS + 0.08, true, false, true).timeout
	await _mouse_button(point, false)
	assert(not toolbar.hold_menu.visible)
	host.queue_free()
	await process_frame
	await process_frame
	print("PASS: single/double/hold selection, release safety, cancellation, pause, outside-click capture and placement")
	quit()


func _check_hold(button: Button, outside: Vector2) -> void:
	var point := button.get_global_rect().get_center()
	await _mouse_button(point, true)
	await create_timer(CityToolbar.HOLD_SECONDS + 0.08, true, false, true).timeout
	assert(toolbar.hold_menu.visible, "Holding a category opens its submenu")
	await _mouse_button(point, false)
	assert(toolbar.hold_menu.visible, "Releasing the original hold keeps the submenu open")
	var choice := toolbar.child_tool_buttons[1] as Button
	var choice_point := Vector2(toolbar.hold_menu.position) + choice.get_global_rect().get_center() * toolbar.hold_menu.content_scale_factor
	await _click(choice_point)
	assert(not toolbar.hold_menu.visible and selected == 1, "One submenu click selects and closes")
	await _click(point)
	assert(not toolbar.hold_menu.visible and selected == 1, "A later single click retains the selected tool")
	# A short press, moving away, hiding, or a disabled button must not leave a
	# delayed popup behind. Use real pointer events rather than timer internals.
	await _mouse_button(point, true)
	await _mouse_button(point, false)
	await create_timer(CityToolbar.HOLD_SECONDS + 0.08, true, false, true).timeout
	assert(not toolbar.hold_menu.visible, "A short click does not become a delayed hold")
	await _mouse_button(point, true)
	var motion := InputEventMouseMotion.new()
	motion.position = outside
	Input.parse_input_event(motion)
	await create_timer(CityToolbar.HOLD_SECONDS + 0.08, true, false, true).timeout
	assert(not toolbar.hold_menu.visible, "Leaving the category cancels the hold")
	await _mouse_button(outside, false)
	await _mouse_button(point, true)
	toolbar.hide()
	await create_timer(CityToolbar.HOLD_SECONDS + 0.08, true, false, true).timeout
	toolbar.show()
	await _mouse_button(point, false)
	assert(not toolbar.hold_menu.visible, "A hidden toolbar cannot open a pending menu")
	await _mouse_button(point, true)
	button.disabled = true
	await create_timer(CityToolbar.HOLD_SECONDS + 0.08, true, false, true).timeout
	await _mouse_button(point, false)
	assert(not toolbar.hold_menu.visible, "A disabled category cannot open a hold menu")
	button.disabled = false
	await _mouse_button(point, true)
	toolbar.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await create_timer(CityToolbar.HOLD_SECONDS + 0.08, true, false, true).timeout
	await _mouse_button(point, false)
	assert(not toolbar.hold_menu.visible, "Losing window focus cancels a pending hold")
	toolbar.process_mode = Node.PROCESS_MODE_ALWAYS
	paused = true
	await _mouse_button(point, true)
	await create_timer(CityToolbar.HOLD_SECONDS + 0.08, true, false, true).timeout
	assert(toolbar.hold_menu.visible, "The hold uses real UI time while simulation is paused")
	await _mouse_button(point, false)
	paused = false
	toolbar.hold_menu.hide()
	await process_frame


func _click(point: Vector2, double := false) -> void:
	await _mouse_button(point, true, double)
	await _mouse_button(point, false)


func _mouse_button(point: Vector2, down: bool, double := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.double_click = double and down
	Input.parse_input_event(event)
	await process_frame
	await process_frame
