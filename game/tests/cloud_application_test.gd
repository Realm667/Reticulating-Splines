extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.gui_embed_subwindows = true
	AppPaths.use_executable_folder(ProjectSettings.globalize_path("res://../cloud-application-profile-" + Crypto.new().generate_random_bytes(8).hex_encode()), true)
	var app := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	preload("res://tests/support/app_fixture.gd").configure(app, true)
	var started := {"ready": false}
	app.startup_finished.connect(func() -> void: started.ready = true)
	root.add_child(app)
	while not started.ready:
		await process_frame
	assert(app.coop.city_file is CityOpenDialog and (app.coop.city_file as CityOpenDialog).cloud_panel.sync == app.cloud,
		"Multiplayer continuation uses the same separate Local and Cloud libraries")
	app.set_process(false)
	app.cloud.account = {"id": "application-test"}
	app.cloud.queue = CloudQueue.new()
	assert(app.cloud.queue.open(AppPaths.path("cloud-test"), "application-test"))
	var document := Sc2xDocument.create_empty(16, "Cloud application").document
	assert(app.city_session.activate_document(document))
	var path := AppPaths.path("cities").path_join("cloud-application.sc2x")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	app.cloud.set_enabled(path, true)
	assert(app.city_files._save_copy(path))
	assert(FileAccess.file_exists(path))
	assert(app.cloud.queue.state.jobs.size() == 1)
	var queued: Dictionary = app.cloud.queue.state.jobs[0]
	assert(app.cloud.queue.bytes(queued) == FileAccess.get_file_as_bytes(path))
	assert(not app.city_files._city_has_unsaved_changes(), "Enqueue cannot dirty the saved city")
	var old_bytes := app.cloud.queue.bytes(queued)
	document.set_misc_i32(Sc2MiscLayout.FUNDS, 12345)
	assert(app.cloud.queue.bytes(queued) == old_bytes, "Subsequent play cannot mutate a queued version")
	assert(app.city_files._save_copy(path))
	assert(app.cloud.queue.state.jobs.size() == 2)
	app.cloud.set_enabled(path, false)
	document.set_misc_i32(Sc2MiscLayout.FUNDS, 4567)
	assert(app.city_files._save_copy(path))
	assert(app.cloud.queue.state.jobs.size() == 2, "Local-only saves must not enqueue")
	assert(not app.city_files._city_has_unsaved_changes())
	app.queue_free()
	await process_frame
	print("PASS real application local save, immutable Cloud queue, dirty-state and opt-out")
	quit()
