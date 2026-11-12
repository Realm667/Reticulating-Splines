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
	assert(toolbar.hold_menu.visible, "A short click opens the menu without a hold delay")
	toolbar.hold_menu.hide()
	await process_frame
	await _click(road_button.get_global_rect().get_center())
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
	await _click(toolbar.toolbar_buttons[CityToolIds.Group.ROADS].get_global_rect().get_center())
	await process_frame
	toolbar.set_landscape_editor(true)
	assert(not toolbar.hold_menu.visible)
	host.queue_free()
	await process_frame
	await process_frame
	print("PASS: flyout outside-click capture, next-click recovery, edge placement and editor dismissal")
	quit()


func _click(point: Vector2) -> void:
	await _mouse_button(point, true)
	await _mouse_button(point, false)


func _mouse_button(point: Vector2, down: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	await process_frame
	await process_frame
