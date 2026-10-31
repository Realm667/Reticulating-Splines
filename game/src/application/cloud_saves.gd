class_name ApplicationCloudSaves
extends RefCounted
## Captures complete, verified local checkpoints before the network sees them.
@warning_ignore_start("integer_division")

var app: CityApplication
var elapsed := 0.0
var task := -1
var job: Dictionary = {}
var last_signature: Array = []
var pending_opt_in := ""

func _init(application: CityApplication) -> void:
	app = application

func initialize() -> void:
	app.cloud = CloudSync.new()
	app.cloud_ui = CloudWindow.new()
	app.add_child(app.cloud)
	app.cloud.configure()
	app.add_child(app.cloud_ui)
	app.cloud_ui.bind(app.cloud)
	app.cloud.changed.connect(_resume_opt_in)
	app.cloud_ui.opt_in_changed.connect(func(path: String, enabled: bool) -> void:
		if enabled:
			saved(path))
	app.cloud_ui.downloaded.connect(func(path: String) -> void: app.city_files.load_city(path))
	app.cloud.start()

func choose(path: String, enabled: bool) -> void:
	if not enabled:
		pending_opt_in = ""
		if not app.cloud.account.is_empty():
			app.cloud.set_enabled(path, false)
		return
	if app.cloud.account.is_empty():
		pending_opt_in = path
		app.cloud_ui.set_current_path(path)
		app.cloud_ui.open()
	else:
		app.cloud.set_enabled(path, true)

func _resume_opt_in() -> void:
	if pending_opt_in.is_empty() or app.cloud.account.is_empty() or app.cloud.queue == null:
		return
	var path := pending_opt_in
	pending_opt_in = ""
	app.cloud.set_enabled(path, true)
	saved(path)

func process(delta: float) -> void:
	if task >= 0 and WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
		if job.get("ok", false):
			app.cloud.saved(job.path, FileAccess.get_file_as_bytes(job.snapshot), job.metadata)
			DirAccess.remove_absolute(job.snapshot)
		else:
			last_signature = []
		job.clear()
	var path: String = app.coop.multiplayer_save_path if app.coop.active() else app.document_state.current_save_path
	app.cloud_ui.set_current_path(path)
	elapsed += delta
	if elapsed < 300.0 or task >= 0 or path.is_empty() or not app.cloud.is_enabled(path):
		return
	elapsed = 0.0
	if app.coop.active() and not app.coop.session.hosting:
		return
	var document := app.document_state.current_document
	if document == null:
		return
	var signature := ApplicationAutosave._content_signature(document)
	if signature == last_signature:
		return
	var copy: Sc2File
	if app.coop.active():
		var checkpoint := app.coop.session.city_checkpoint()
		if not checkpoint.error.is_empty():
			return
		copy = checkpoint.document
	else:
		if not app.regions.prepare_save().is_empty() or not Sc2xCheckpoint.save_error(app.simulation_state.speed_controller).is_empty():
			return
		copy = document.duplicate_document(true)
		if copy.is_sc2x():
			Sc2xCheckpoint.capture(app.simulation_state.speed_controller, copy.sc2x_metadata)
	var folder := AppPaths.path("cloud").path_join("checkpoints")
	DirAccess.make_dir_recursive_absolute(folder)
	var snapshot := folder.path_join("checkpoint-" + str(Time.get_ticks_usec()) + (".sc2x" if copy.is_sc2x() else ".SC2"))
	var prepared := CityFileStore.prepare(copy, snapshot, app.asset_state.reference_root)
	if not prepared.ok:
		return
	last_signature = signature
	job = {"path": path, "snapshot": snapshot, "metadata": metadata(copy), "ok": false}
	var work := job
	task = WorkerThreadPool.add_task(func() -> void:
		work.ok = CityFileStore.write(prepared).ok)

func saved(path: String) -> void:
	if app.coop.active() and not app.coop.session.hosting:
		return
	if app.cloud.is_enabled(path):
		app.cloud.saved(path, FileAccess.get_file_as_bytes(path), metadata(app.document_state.current_document))
		elapsed = 0.0

func metadata(document: Sc2File) -> Dictionary:
	if document == null:
		return {}
	var city := CityState.from_document(document)
	return {"name": document.city_name(), "kind": "multiplayer" if app.coop.active() else "region" if document.sc2x_extra_entries.has(RegionCampaign.ENTRY) else "city",
		"population": city.population(), "year": city.founding_year() + city.age_in_days() / CityCalendar.DAYS_PER_YEAR,
		"host_authorized": app.coop.session.hosting if app.coop.active() else true}

func close() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)
		# Keep a completed local checkpoint in the durable queue before shutdown.
		if job.get("ok", false):
			app.cloud.saved(job.path, FileAccess.get_file_as_bytes(job.snapshot), job.metadata)
		task = -1
