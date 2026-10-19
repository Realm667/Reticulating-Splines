class_name TutorialProgress
extends RefCounted
## Local learning records, keyed by saved city bytes. No SC2 chunks.

const VERSION := 1
var path := "user://tutorial-progress.json"
var data: Dictionary = {"version": VERSION, "invited": false, "advisor": 0, "hidden": [], "records": {}}
var key := ""
var record: Dictionary = {}


func load_store() -> void:
	if not FileAccess.file_exists(path):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return
	var parsed: Variant = parser.data
	if not parsed is Dictionary or parsed.get("version") != VERSION or not parsed.get("records") is Dictionary:
		return
	data.invited = parsed.get("invited", false) == true
	var advisor: Variant = parsed.get("advisor", 0)
	data.advisor = clampi(int(advisor), 0, 2) if advisor is float or advisor is int else 0
	var hidden: Variant = parsed.get("hidden", [])
	if hidden is Array:
		for topic in hidden:
			if topic in ["power", "water", "budget", "growth", "disaster"]:
				data.hidden.append(topic)
	for saved_key in parsed.records:
		var saved: Variant = parsed.records[saved_key]
		if not saved_key is String or not saved is Dictionary:
			continue
		var clean := {"current": "", "states": {}, "checkpoints": {}, "practice": saved.get("practice", false) == true}
		var current: Variant = saved.get("current", "")
		if current is String and not TutorialCatalog.lesson(current).is_empty():
			clean.current = current
		if saved.get("exercise", "") == "utilities_outage":
			clean.exercise = "utilities_outage"
		var states: Variant = saved.get("states", {})
		if states is Dictionary:
			for id in states:
				if id is String and not TutorialCatalog.lesson(id).is_empty() and states[id] in ["done", "later", "skipped"]:
					clean.states[id] = states[id]
		var checkpoints: Variant = saved.get("checkpoints", {})
		if checkpoints is Dictionary:
			for chapter in checkpoints:
				if chapter is String and checkpoints[chapter] is String:
					clean.checkpoints[chapter] = checkpoints[chapter]
		data.records[saved_key] = clean


func bind_city(file_path: String) -> void:
	key = FileAccess.get_sha256(file_path) if FileAccess.file_exists(file_path) else ""
	record = data.records.get(key, {}).duplicate(true) if not key.is_empty() else {}
	record.erase("ready")


func saved_city(file_path: String) -> Error:
	var next_key := FileAccess.get_sha256(file_path)
	if next_key.is_empty():
		return ERR_FILE_CANT_READ
	key = next_key
	return write()


func write() -> Error:
	if not key.is_empty():
		data.records[key] = record.duplicate(true)
	var folder := ProjectSettings.globalize_path(path).get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK:
		return error
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
