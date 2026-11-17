class_name MultiplayerCopyDialog
extends RefCounted

static func choose(app: CityApplication, document: Sc2File, path: String) -> void:
	var validated := MultiplayerSingleplayer.convert(document)
	if not validated.error.is_empty():
		app.interface.show_error(_tr(validated.error))
		return
	var data := MultiplayerSingleplayer.metadata(document)
	var dialog := app.coop.windows.make_window("Open multiplayer save")
	var box := app.coop.windows.content(dialog)
	ApplicationMultiplayer.label(box, "Open a single-player copy or continue multiplayer.")
	var region: bool = data.get("shared", {}).get("mode") == "region"
	var picker := OptionButton.new()
	var actors: Array = data.get("shared", {}).get("actors", [])
	if region:
		box.add_child(picker)
		for actor: String in actors:
			var entry: Dictionary = data.get("members", {}).get(actor, {})
			var city := Sc2File.new()
			city.parse(Marshalls.base64_to_raw(str(data.shared.cities[actor].state.city)))
			picker.add_item(str(entry.get("name", "")) + " · " + CityState.from_document(city).city_name())
	elif data.has("shared"):
		var note := ApplicationMultiplayer.label(box, "All cities merge: shared terrain once, combined funds and bank bonds, internal player loans cancel. Host tax and funding settings apply. More than 50 bank bonds are repaid from combined funds.")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ApplicationMultiplayer.button(box, "Open single-player copy", func() -> void:
		var converted := MultiplayerSingleplayer.convert(document, str(actors[picker.selected]) if region and not actors.is_empty() else "")
		if not converted.error.is_empty():
			app.interface.show_error(_tr(converted.error))
			return
		app.city_files.pending_multiplayer_copy = converted.document
		app.city_files.pending_multiplayer_source = path
		app.city_files.request_city_exit("multiplayer_copy")
		dialog.queue_free())
	ApplicationMultiplayer.button(box, "Continue multiplayer", func() -> void:
		app.coop.open()
		app.coop.city_picker.select(1)
		app.coop.use_current.show()
		app.coop.use_current.button_pressed = false
		app.coop.selected_city_path = path
		app.coop.city_file.current_path = path
		dialog.queue_free())
	dialog.popup_centered()

static func host_ended(coop: ApplicationMultiplayer) -> void:
	if coop.ended_dialog != null:
		return
	var encoded := str(coop.session.ended_city if not coop.session.ended_city.is_empty() else coop.session.confirmed_own_city)
	var city := Sc2File.new()
	var valid := not encoded.is_empty() and city.parse(Marshalls.base64_to_raw(encoded))
	if not valid and not coop.session.confirmed_own_state.is_empty():
		var confirmed := MultiplayerDocument.restore(coop.session.confirmed_own_state)
		if confirmed != null:
			city = MultiplayerSingleplayer.clean(confirmed)
			valid = true
	# For an old host or a failed final transfer, only use a confirmed OWN view.
	if not valid and not coop.session.latest.get("visiting", false) and coop.app.document_state.current_document != null:
		city = MultiplayerSingleplayer.clean(coop.app.document_state.current_document)
		valid = true
	coop.ended_dialog = coop.windows.make_window("Session ended")
	coop.ended_dialog.exclusive = true
	coop.ended_dialog.set_meta("center_after_fit", true)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	coop.ended_dialog.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	MultiplayerDialogFit.bind(coop.ended_dialog, box, 680)
	ApplicationMultiplayer.label(box, "The host ended the game. Save a single-player copy before leaving.")
	var status := ApplicationMultiplayer.label(box, "")
	status.hide()
	if not valid:
		status.text = _tr("No confirmed copy of your city is available.")
		status.show()
	var save := ApplicationMultiplayer.button(box, "Save city copy", func() -> void:
		var file := FileDialog.new()
		file.theme = AppUiTheme.current()
		file.access = FileDialog.ACCESS_FILESYSTEM
		file.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		file.filters = PackedStringArray(["*.sc2x ; " + str(TranslationServer.translate("Single-player city"))])
		var save_directory := AppPaths.path("cities")
		DirAccess.make_dir_recursive_absolute(save_directory)
		file.current_dir = save_directory
		file.current_file = CityState.from_document(city).city_name().validate_filename() + "-singleplayer.sc2x"
		coop.ended_dialog.add_child(file)
		file.canceled.connect(file.queue_free)
		file.file_selected.connect(func(path: String) -> void:
			status.show()
			if not path.to_lower().ends_with(".sc2x"):
				path += ".sc2x"
			# This flow deliberately creates a new file; it never replaces a city.
			if FileAccess.file_exists(path):
				status.text = _tr("Choose a new filename; existing cities are kept.")
				file.queue_free()
				return
			var error := CoopSession.write_document(city, path)
			status.text = _tr("City copy saved.") if error.is_empty() else _tr(error)
			file.queue_free())
		file.popup_centered_ratio(0.8))
	save.disabled = not valid
	var leave := func() -> void:
		coop.ended_dialog.queue_free()
		coop.ended_dialog = null
		coop.leave()
	ApplicationMultiplayer.button(box, "Leave game", leave)
	coop.ended_dialog.close_requested.connect(leave)
	coop.ended_dialog.popup_centered()

static func _tr(value: String) -> String:
	return TranslationServer.translate(value)
