class_name CityPhotoMode
extends Node
## A temporary presentation state. No city, speed or saved preference is changed.

var app: CityApplication
var active := false
var capturing := false
var panel: PanelContainer
var notice: Label
var _save_button: Button
var _city: CityState
var _edit_enabled := false
var _selection_mode := "rectangle"
var _footprint := 1
var _controls_visible := true
var _hidden: Array[CanvasItem] = []


func _init(application: CityApplication) -> void:
	app = application


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	panel = PanelContainer.new()
	panel.theme_type_variation = "FloatingPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = -82
	panel.offset_bottom = -16
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := Label.new()
	title.text = "Photo mode"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	for entry in [["Save photo", capture], ["Open photo folder", open_folder], ["Exit photo mode", close]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		row.add_child(button)
		if _save_button == null:
			_save_button = button
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(notice)
	panel.hide()
	set_process(false)


func open() -> void:
	if active or app.document_state.city == null or app.tool_state.landscape_editor:
		return
	if app.city_dialogs.blocks_simulation() or app.main_overlays.blocks_simulation():
		app.interface.show_error(tr("Close other dialogs before entering photo mode."))
		return
	for window in app.get_viewport().get_embedded_subwindows():
		if window.visible and not window is PopupMenu:
			app.interface.show_error(tr("Close other dialogs before entering photo mode."))
			return
	_city = app.document_state.city
	_edit_enabled = app.map_view.edit_enabled
	_selection_mode = app.map_view.selection_mode
	_footprint = app.map_view.point_footprint_area
	_controls_visible = app.city_workspace.get_node("Page").visible
	active = true
	app.map_view.photo_mode_active = true
	app.map_view.set_edit_enabled(false)
	app.city_workspace.set_editor_controls_visible(false)
	_hidden.clear()
	for item in [app.map_view.layers.overlay_layer]:
		if item != null and item.visible:
			_hidden.append(item)
			item.hide()
	panel.theme = AppUiTheme.current()
	notice.text = tr("Pan and zoom to frame the photo. Escape exits. Multiplayer continues running.") if app.coop.active() else tr("Pan and zoom to frame the photo. Escape exits. The city is paused.")
	panel.show()
	_save_button.grab_focus()
	set_process(true)


func close() -> void:
	if not active or capturing:
		return
	active = false
	app.map_view.photo_mode_active = false
	panel.hide()
	app.city_workspace.set_editor_controls_visible(_controls_visible)
	if app.document_state.city == _city:
		app.map_view.set_edit_enabled(_edit_enabled, _selection_mode, _footprint)
	for item in _hidden:
		if is_instance_valid(item):
			item.show()
	_hidden.clear()
	_city = null
	set_process(false)


func _process(_delta: float) -> void:
	if app.document_state.city != _city and not capturing:
		close()


func input(event: InputEvent) -> bool:
	if not active or not event is InputEventKey:
		return false
	# Let the photo bar receive standard keyboard focus and activation keys.
	if event.keycode == KEY_TAB or (event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
			and panel.is_ancestor_of(app.get_viewport().gui_get_focus_owner())):
		return false
	if not event.pressed:
		app.view_state.camera_motion.release(ApplicationControls.key_id(event))
	if event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
		elif app.controls.press_hold_key(event):
			pass
		else:
			var action := app.controls.bindings().action_for(event, [ControlActions.KIND_PRESS])
			if action in ["zoom_in", "zoom_out", "zoom_reset", "rotate_clockwise", "rotate_counter_clockwise"]:
				app.controls.run(action)
	# Camera movement polls held keys. Consume shortcuts that could edit the city.
	return true


func capture() -> void:
	if not active or capturing:
		return
	capturing = true
	panel.hide()
	# Wait for a complete frame without the photo controls.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := app.get_viewport().get_texture().get_image()
	var folder := AppPaths.path("screenshots")
	var error := DirAccess.make_dir_recursive_absolute(folder)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := folder.path_join("RS-%s-%d.png" % [stamp, Time.get_ticks_usec()])
	if error == OK:
		error = image.save_png(path) if image != null else ERR_CANT_CREATE
	capturing = false
	if error == OK and app.tutorial != null:
		app.tutorial.mark("photo")
	panel.show()
	notice.text = tr("Photo saved: %s") % path if error == OK else tr("Could not save photo: %s") % error_string(error)


func open_folder() -> void:
	var folder := AppPaths.path("screenshots")
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error == OK:
		error = OS.shell_open(ProjectSettings.globalize_path(folder))
	if error != OK:
		notice.text = tr("Could not open photo folder: %s") % error_string(error)
