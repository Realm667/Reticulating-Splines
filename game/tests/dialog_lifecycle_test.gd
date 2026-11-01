extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	preload("res://tests/support/app_fixture.gd").configure(main)
	root.add_child(main)
	await process_frame
	assert(main.scurk_editor == null and main.scurk_place_print == null and main.scurk_print == null)
	assert(main.main_overlays.scurk_workspace == null)
	for scene_name in ["scurk_editor_control", "scurk_place_print_control", "scurk_print_control"]:
		assert(not ResourceLoader.has_cached("res://src/ui/scurk/%s.tscn" % scene_name), "Unexpected cached scene: " + scene_name)
	main.new_city.open_new_city_dialog()
	assert(main.city_dialogs.new_city_dialog.visible)
	assert(main.main_overlays.scurk_workspace == null)
	main.city_dialogs.new_city_dialog.hide()
	main.scurk_workspace.ensure_scurk_place_print()
	assert(main.scurk_editor == null and main.scurk_print == null)
	assert(main.scurk_city_export_dialog.get_parent() == main.scurk_place_print)
	main.scurk_output._ensure_scurk_print()
	assert(main.scurk_print.get_parent() == main.scurk_place_print)
	assert(main.scurk_print_pdf_dialog.get_parent() == main.scurk_print)
	main.scurk_workspace._ensure_scurk_editor()
	var editor: ScurkEditorControl = main.scurk_editor
	assert(editor.get_parent() == main.main_overlays.scurk_workspace)
	assert(not editor.visible and not main.scurk_place_print.visible and not main.scurk_print.visible)
	main.scurk_workspace._ensure_scurk_editor()
	assert(main.scurk_editor == editor)
	main.queue_free()
	await process_frame
	await _touch_dismissal()
	print("PASS: New City excludes SCURK; lazy windows own their prompts and are reused")
	quit()


func _touch(index: int, point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _touch_dismissal() -> void:
	root.size = Vector2i(800, 600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var router := TouchDialogDismiss.new()
	root.add_child(router)
	router.attach(root)
	var backdrop := Button.new()
	backdrop.size = Vector2(800, 600)
	var clicks: Array = []
	backdrop.pressed.connect(func() -> void: clicks.append(true))
	root.add_child(backdrop)
	var dialog := ConfirmationDialog.new()
	dialog.size = Vector2i(320, 200)
	dialog.position = Vector2i(240, 200)
	dialog.exclusive = true
	var canceled: Array = []
	var confirmed: Array = []
	dialog.canceled.connect(func() -> void: canceled.append(true))
	dialog.confirmed.connect(func() -> void: confirmed.append(true))
	root.add_child(dialog)
	dialog.popup()
	await process_frame
	var inside := root.get_final_transform() * (Vector2(dialog.position) + Vector2(dialog.size) * 0.5)
	_touch(0, inside, true)
	_touch(0, inside, false)
	await process_frame
	assert(dialog.visible, "Inside taps keep the dialog open")
	_touch(0, Vector2(50, 50), true)
	assert(dialog.visible, "Outside press waits for release and consumes the contact")
	_touch(0, Vector2(50, 50), false, true)
	await process_frame
	assert(dialog.visible and canceled.is_empty(), "Canceled contacts do not dismiss")
	_touch(0, Vector2(50, 50), true)
	_touch(1, Vector2(80, 50), true)
	_touch(0, Vector2(50, 50), false)
	_touch(1, Vector2(80, 50), false)
	await process_frame
	assert(dialog.visible, "Two-finger gestures do not dismiss dialogs")
	_touch(0, Vector2(50, 50), true)
	_touch(0, Vector2(50, 50), false)
	await process_frame
	assert(not dialog.visible and canceled.size() == 1 and confirmed.is_empty(), "Outside tap follows close/cancel, never confirmation")
	assert(clicks.is_empty(), "Touch and emulated mouse do not click through")
	# The same rule applies to modeless utility windows and nested prompts.
	var parent := QolDialog.new()
	root.add_child(parent)
	parent.position = Vector2i(220, 180)
	parent.show()
	root.remove_child(dialog)
	parent.add_child(dialog)
	dialog.popup()
	await process_frame
	_touch(0, Vector2(40, 40), true)
	_touch(0, Vector2(40, 40), false)
	await process_frame
	assert(not dialog.visible and parent.visible, "Only the frontmost nested prompt closes")
	_touch(0, Vector2(40, 40), true)
	_touch(0, Vector2(40, 40), false)
	await process_frame
	assert(not parent.visible and clicks.is_empty(), "Modeless dialogs also consume the dismissal tap")
	parent.queue_free()
	backdrop.queue_free()
	router.queue_free()
	await process_frame
