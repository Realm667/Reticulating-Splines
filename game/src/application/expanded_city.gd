class_name ExpandedCity
extends RefCounted
## Explicit one-way city conversion. Existing files are never overwritten.


static func open(app: CityApplication) -> void:
	var city := app.document_state.city
	if city == null:
		app.interface.show_error("No city is loaded.")
		return
	if ExpandedRules.enabled(city.document):
		app.interface.show_error("This city uses Expanded rules. It cannot return to Classic.")
		return
	if app.coop.active():
		app.interface.show_error("Change city rules before hosting a multiplayer game.")
		return
	var expected := city.document
	var dialog := ConfirmationDialog.new()
	dialog.title = "Switch to Expanded?"
	dialog.dialog_text = "Expanded adds eight metropolis rewards. This city cannot return to Classic. Save a separate SC2X copy to keep your Classic city."
	dialog.get_ok_button().text = "Switch to Expanded"
	dialog.theme = AppUiTheme.current()
	dialog.exclusive = true
	app.add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		if expected == app.document_state.current_document:
			ExpandedCity.upgrade(app)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(560, 180))


static func upgrade(app: CityApplication) -> void:
	var error := Sc2xCheckpoint.save_error(app.simulation_state.speed_controller)
	if not error.is_empty():
		app.interface.show_error(TranslationServer.translate(error))
		return
	var source := app.document_state.current_document
	var document: Sc2File
	if source.is_sc2x():
		document = source.duplicate_document()
	else:
		var converted := Sc2xDocument.from_legacy(source, source.city_name())
		if not converted.ok:
			app.interface.show_error(TranslationServer.translate(converted.error))
			return
		document = converted.document
	Sc2xCheckpoint.capture(app.simulation_state.speed_controller, document.sc2x_metadata)
	error = ExpandedRules.enable(document)
	if not error.is_empty():
		app.interface.show_error(TranslationServer.translate(error))
		return
	document.sc2x_converted_from = source.source_path
	if app.city_session.activate_document(document, app.simulation_state.simulation_engine.scenario, "Expanded rules enabled.", true):
		app.document_state.current_save_path = ""
		app.document_state.current_city_saved_once = false
		app.city_files.open_save_dialog()
