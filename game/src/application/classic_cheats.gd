class_name ApplicationClassicCheats
extends RefCounted
## Desktop codes are local input, never multiplayer commands or chat messages.

const Disasters = preload("res://src/simulation/disasters/disaster_start_phase.gd")
const JACKPOTS: PackedStringArray = ["imacheat", "buddamus", "torg", "porntipsguzzardo", "pirntopsguzzardo"]

var app: CityApplication
var recognizer := ClassicCheatInput.new()
var _document: Sc2File
var _jackpot := false
var _mac_prefix := false
var _scope := ""
var _bond: ConfirmationDialog
var _effect: ClassicEasterEgg


func _init(application: CityApplication) -> void:
	app = application


func allowed() -> bool:
	return ClassicCheatActions.allowed(app.document_state.current_document, app.coop.session, app.coop.mirrored)


func reset_input() -> void:
	recognizer.clear()
	_scope = ""


func _sync_document() -> void:
	if _document != app.document_state.current_document or not allowed():
		_document = app.document_state.current_document
		_jackpot = false
		_mac_prefix = false
		reset_input()
		if is_instance_valid(_bond):
			_bond.queue_free()
			_bond = null
		if is_instance_valid(_effect):
			_effect.queue_free()
			_effect = null


func _input_scope() -> String:
	if not allowed() or not DisplayServer.window_is_focused():
		return ""
	var focus := app.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return ""
	if app.scurk_editor != null and app.scurk_editor.visible:
		for window in app.get_viewport().get_embedded_subwindows():
			if window.visible:
				return ""
		return "scurk"
	return "city" if app.camera_input.camera_keys_allowed() else ""


func process() -> void:
	_sync_document()
	if recognizer.buffer.is_empty():
		return
	var scope := _input_scope()
	if scope.is_empty() or scope != _scope:
		reset_input()
		return
	recognizer.expire(Time.get_ticks_msec())
	_replay()


func input(event: InputEvent) -> bool:
	_sync_document()
	var scope := _input_scope()
	if scope.is_empty():
		reset_input()
		return false
	if scope != _scope:
		reset_input()
		_scope = scope
	if event is InputEventMouseButton:
		reset_input()
		return false
	if not event is InputEventKey:
		return false
	var handled := recognizer.feed(event, Time.get_ticks_msec(), scope == "scurk")
	_replay()
	if not recognizer.completed.is_empty():
		var code := recognizer.completed
		recognizer.completed = ""
		var ok := execute(code)
		_feedback(code, ok)
	return handled


func _feedback(code: String, ok: bool) -> void:
	var message := (tr("Cheat activated: %s") if ok else tr("Cheat unavailable: %s")) % code
	if app.city_status_bar != null:
		app.city_status_bar.show_notice(message, true)


func _replay() -> void:
	var events := recognizer.released.duplicate()
	recognizer.released.clear()
	for event: InputEventKey in events:
		if _input_scope() != _scope:
			reset_input()
			return
		if not event.pressed:
			app.camera_input.input(event)
		elif _scope == "scurk":
			app.scurk_editor.handle_shortcut(event)
		elif not app.controls.press_hold_key(event):
			app.controls.handle_key(event)


func execute(raw_code: String) -> bool:
	_sync_document()
	if not allowed() or app.document_state.city == null:
		return false
	var code := raw_code.strip_edges().to_lower()
	var city := app.document_state.city
	var engine := app.simulation_state.simulation_engine
	if code in JACKPOTS or (code == "topsguzzardo" and _mac_prefix):
		if not app.debug.debug_unlock_everything().ok or not app.debug.debug_add_funds(500000).ok:
			return false
		_jackpot = true
		_mac_prefix = false
		return true
	match code:
		"pirn":
			_mac_prefix = true
			return true
		"ardo":
			return _jackpot and app.debug.debug_add_funds(500000).ok
		"cass":
			if not app.debug.debug_add_funds(250).ok:
				return false
			if engine != null and not city.no_disasters_enabled() and engine.random.next_u15() % 100 < 15:
				app.debug.debug_start_disaster(Disasters.DISASTER_FIRESTORM)
			return true
		"fund":
			return _offer_bond()
		"priscilla", "oivaizmir":
			if app.debug_overlay == null:
				return false
			if not app.debug_overlay.is_open:
				app.debug_overlay.toggle()
			return true
		"gilmartin":
			return app.debug.debug_offer_military_base().ok
		"noah":
			return engine != null and app.debug.debug_start_disaster(Disasters.DISASTER_MASS_FLOODS).ok
		"mrsoleary":
			return engine != null and app.debug.debug_start_disaster(Disasters.DISASTER_FIRESTORM).ok
		"gomorrah":
			return engine != null and app.debug.debug_start_disaster(Disasters.DISASTER_MELTDOWN).ok
		"moses":
			return (engine != null and engine.active_disaster_type in [Disasters.DISASTER_FLOOD, Disasters.DISASTER_MASS_FLOODS]
				and app.debug.debug_end_disaster().ok)
		"damn", "darn", "heck":
			if ClassicCheatActions.churches(city) == 0:
				return false
			app.tool_state.last_edit_command = null
			if engine != null:
				engine.refresh_city_status()
			app.map_render.refresh_map(true)
			app.interface.refresh_details()
			return true
		"uspa87419", "vaudeville":
			return _show_easter_egg(code == "vaudeville")
	return false


func _offer_bond() -> bool:
	if is_instance_valid(_bond):
		return false
	var expected := app.document_state.current_document
	_bond = ConfirmationDialog.new()
	_bond.theme = AppUiTheme.current()
	_bond.title = tr("Bond")
	_bond.dialog_text = tr("Issue a $10,000 bond at %d%%?") % 25
	_bond.exclusive = true
	_bond.min_size = Vector2i(450, 150)
	app.add_child(_bond)
	_bond.confirmed.connect(func() -> void:
		var ok := confirm_bond(expected)
		_feedback("fund", ok)
		_bond.queue_free()
		_bond = null)
	_bond.canceled.connect(func() -> void:
		_bond.queue_free()
		_bond = null)
	_bond.popup_centered()
	return true


func confirm_bond(expected: Sc2File) -> bool:
	# Recheck after the modal answer; a session or another city may have opened.
	if not allowed() or expected != app.document_state.current_document:
		return false
	var ok := ClassicCheatActions.issue_expensive_bond(app.document_state.city)
	if ok:
		app.interface.refresh_details()
	return ok


func _show_easter_egg(dancing: bool) -> bool:
	var texture: Texture2D
	if dancing:
		var archive := app.asset_state.large_sprites
		if archive == null or app.asset_state.palette == null:
			return false
		var entry := archive.find_sprite(ScurkSpriteIds.LARGE_FIRST + BuildingTileIds.LAUNCH_ARCOLOGY)
		if entry == null:
			return false
		var rendered := entry.create_image(app.asset_state.palette)
		if not rendered.ok:
			return false
		texture = ImageTexture.create_from_image(rendered.image)
	if is_instance_valid(_effect):
		_effect.queue_free()
	_effect = ClassicEasterEgg.new()
	_effect.arcology = texture
	var expected := app.document_state.current_document
	_effect.permitted = func() -> bool: return allowed() and app.document_state.current_document == expected
	app.add_child(_effect)
	return true
