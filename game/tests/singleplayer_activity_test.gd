extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func run() -> void:
	for document: Sc2File in [EmptyCityTemplate.create(), Sc2xDocument.create_empty(128, "Identity").document]:
		var original := document.find_chunk("MISC").decoded_payload.duplicate()
		var identity := CityActivityIdentity.ensure(document)
		check(CityActivityIdentity.valid(identity), "256-bit opaque identity")
		check(CityActivityIdentity.ensure(document) == identity, "identity stable in memory")
		var encoded := document.serialize(true)
		var restored := Sc2File.new()
		check(encoded.ok and restored.parse(encoded.data), "identity file round trip")
		check(CityActivityIdentity.read(restored) == identity, "identity survives SC2 and SC2X")
		check(restored.find_chunk("MISC").decoded_payload == original, "simulation bytes unchanged")
		check(CityActivityIdentity.read(document.duplicate_document()) == identity, "Save As keeps identity")
		var converted := Sc2xDocument.from_legacy(document) if not document.is_sc2x() else null
		if converted != null:
			check(converted.ok and CityActivityIdentity.read(converted.document) == identity, "SC2X conversion keeps original identity")
	var old := Sc2xDocument.create_empty(128, "Legacy").document
	var legacy := ("rs-activity-city-v1:" + "a".repeat(32) + ":coop").sha256_text()
	check(CityActivityIdentity.ensure(old, legacy) == legacy, "legacy migration keeps published ID")
	check(CityActivityIdentity.ensure(Sc2xDocument.create_empty(128, "Other").document) != legacy, "new city has fresh identity")
	var clean := MultiplayerSingleplayer.clean(old)
	check(CityActivityIdentity.read(clean) == legacy, "single-player copy retains identity")
	check(SingleplayerActivity.public_name("a\nb\tc") == "abc", "control characters removed from public name")
	var options := AppSettingsStore.SaveOptions.new()
	check(not AppSettingsStore.load_values("user://missing-activity.cfg").share_singleplayer_activity, "opt-in defaults off")
	options.share_singleplayer_activity = true
	AppSettingsStore.save_values(0.0, 0.0, false, "user://activity.cfg", options)
	check(AppSettingsStore.load_values("user://activity.cfg").share_singleplayer_activity, "opt-in persisted")
	options.share_singleplayer_activity = false
	AppSettingsStore.save_values(0.0, 0.0, false, "user://activity.cfg", options)
	check(not AppSettingsStore.load_values("user://activity.cfg").share_singleplayer_activity, "opt-out persisted")
	if OS.get_environment("RS_MULTIPLAYER_URL").begins_with("http://127.0.0.1:"):
		# Consume the expensive fixture-creation frame before timed HTTP work.
		await process_frame
		await process_frame
		await lifecycle()
	print("Single-player activity: %d failure(s)" % failures)
	quit(1 if failures else 0)


func settled(manager: SingleplayerActivity) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		var busy := false
		for child: ActivityReporter in manager.get_children():
			busy = busy or child.pending
		if not busy:
			await process_frame
			return
		await process_frame
	check(false, "HTTP fixture completed before deadline")


func lifecycle() -> void:
	# Construct only the application model: no personal profiles or game startup.
	var app := CityApplication.new()
	app.coop.session = CoopSession.new()
	app.main_menu = MainMenuControl.new()
	app.main_menu.hide()
	app.document_state.current_document = Sc2xDocument.create_empty(128, "Presence fixture").document
	app.document_state.city = CityState.from_document(app.document_state.current_document)
	var manager := SingleplayerActivity.new()
	manager.app = app
	root.add_child(manager)
	manager.set_process(false)
	manager.sync()
	check(manager.reporter == null and CityActivityIdentity.read(app.document_state.current_document).is_empty(), "disabled makes no request or identity mutation")
	app.preferences.share_singleplayer_activity = true
	manager.sync()
	await settled(manager)
	check(manager.reporter.last_code == 200, "initial HTTP registration succeeds: code=%d result=%d start=%d next=%d" % [manager.reporter.last_code, manager.reporter.last_result, manager.reporter.start_error, manager.reporter.next_update])
	var first := manager.reporter.room
	var identity := CityActivityIdentity.read(app.document_state.current_document)
	manager.sync()
	check(not manager.reporter.pending and manager.reporter.room == first, "one minute heartbeat is throttled")
	manager.reporter.next_update = 0
	manager.sync()
	check(manager.reporter.pending, "heartbeat starts asynchronously")
	await settled(manager)
	check(manager.reporter.last_code == 200, "heartbeat HTTP registration succeeds")
	app.coop.session.active = true
	manager.sync()
	await settled(manager)
	check(manager.reporter == null, "entering multiplayer removes solo presence")
	app.coop.session.active = false
	app.tool_state.landscape_editor = true
	manager.sync()
	check(not manager.eligible(), "terrain editor excluded")
	app.tool_state.landscape_editor = false
	app.main_menu.show()
	manager.sync()
	check(not manager.eligible(), "menu demonstration excluded")
	app.main_menu.hide()
	manager.sync()
	await settled(manager)
	check(manager.reporter.room != first and CityActivityIdentity.read(app.document_state.current_document) == identity, "new session retains city ID")
	app.preferences.share_singleplayer_activity = false
	manager.sync()
	await settled(manager)
	check(manager.get_child_count() == 0, "opt-out removes active lease")
	app.preferences.share_singleplayer_activity = true
	manager.sync()
	# Exercise closing while PUT is in flight. DELETE must follow that PUT.
	await manager.shutdown()
	check(manager.get_child_count() == 0, "normal quit retires in-flight presence")
	manager.queue_free()
	app.main_menu.free()
	app.coop.session.free()
	app.free()
	await process_frame
