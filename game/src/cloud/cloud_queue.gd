class_name CloudQueue
extends RefCounted
## Account and endpoint isolated durable manifest, plus content-addressed blobs.
## A blob is published first, then its manifest entry. Interrupted writes can
## leave an unused blob, never a manifest pointing at a partial snapshot.

var directory := ""
var state := {"version": 1, "bindings": {}, "jobs": []}
var error := ""


func open(root_path: String, account_key: String) -> bool:
	directory = root_path.path_join(account_key.sha256_text())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "storage_error"
		return false
	var path := directory.path_join("queue.json")
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"):
		DirAccess.rename_absolute(path + ".bak", path)
	if not FileAccess.file_exists(path):
		return true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("bindings") is Dictionary or not parsed.get("jobs") is Array:
		error = "invalid_queue"
		return false
	for saved_path: Variant in parsed.bindings:
		if not saved_path is String or not parsed.bindings[saved_path] is Dictionary or not parsed.bindings[saved_path].get("enabled") is bool:
			error = "invalid_queue"
			return false
	for job: Variant in parsed.jobs:
		if not job is Dictionary or not job.get("id") is String or not job.get("sha256") is String or job.sha256.length() != 64 or not job.sha256.is_valid_hex_number(false) or not job.get("path") is String or not job.get("metadata") is Dictionary:
			error = "invalid_queue"
			return false
		if not job.get("save_id") is String or not job.get("upload_id") is String or job.get("status") not in ["queued", "retry", "uploading", "conflict", "retained", "done"] or not parsed.bindings.has(job.path) or not (job.get("size") is int or job.get("size") is float) or int(job.size) <= 0 or int(job.size) > Sc2xDocument.MAX_ARCHIVE_BYTES:
			error = "invalid_queue"
			return false
	state = parsed
	return true


func persist() -> bool:
	var bytes := JSON.stringify(state).to_utf8_buffer()
	if not atomic_bytes(directory.path_join("queue.json"), bytes):
		error = "storage_error"
		return false
	return true


func enqueue(path: String, bytes: PackedByteArray, metadata: Dictionary) -> Dictionary:
	var binding: Dictionary = state.bindings.get(path, {})
	if not binding.get("enabled", false):
		return {"ok": true, "skipped": true}
	var sha := CloudSnapshot.digest(bytes)
	if binding.get("last_sha256") == sha:
		return {"ok": true, "skipped": true}
	for existing: Dictionary in state.jobs:
		if existing.path == path and existing.sha256 == sha:
			return {"ok": true, "skipped": true}
	var blob := directory.path_join(sha + ".save")
	if not FileAccess.file_exists(blob) and not atomic_bytes(blob, bytes):
		return {"ok": false, "error": "storage_error"}
	if CloudSnapshot.digest(FileAccess.get_file_as_bytes(blob)) != sha:
		return {"ok": false, "error": "checksum_mismatch"}
	var job := {"id": Crypto.new().generate_random_bytes(16).hex_encode(), "path": path,
		"sha256": sha, "size": bytes.size(), "metadata": metadata.duplicate(true),
		"save_id": binding.get("save_id", ""), "base_revision": binding.get("revision"),
		"upload_id": "", "status": "queued", "error": ""}
	state.jobs.append(job)
	if not persist():
		state.jobs.pop_back()
		return {"ok": false, "error": "storage_error"}
	return {"ok": true, "id": job.id}


func bytes(job: Dictionary) -> PackedByteArray:
	var value := FileAccess.get_file_as_bytes(directory.path_join(str(job.sha256) + ".save"))
	return value if CloudSnapshot.digest(value) == job.sha256 else PackedByteArray()


func prune_completed(keep_per_path := 5) -> bool:
	# Pending, conflicted and explicitly retained branches are never coalesced.
	# Publish the bounded manifest before touching any generated content blob.
	var previous: Array = state.jobs
	var kept: Array = []
	var completed := {}
	for index in range(previous.size() - 1, -1, -1):
		var job: Dictionary = previous[index]
		if job.status == "done":
			var count := int(completed.get(job.path, 0))
			completed[job.path] = count + 1
			if count >= maxi(1, keep_per_path):
				continue
		kept.push_front(job)
	if kept.size() != previous.size():
		state.jobs = kept
		if not persist():
			state.jobs = previous
			return false
	var referenced := {}
	for job: Dictionary in state.jobs:
		referenced[job.sha256] = true
	var folder := DirAccess.open(directory)
	if folder == null:
		error = "storage_error"
		return false
	for filename: String in folder.get_files():
		# This directory is private to this account. Still restrict collection
		# to our exact content-addressed naming scheme, never a job's local path.
		if filename.get_extension() != "save":
			continue
		var sha := filename.get_basename()
		if sha.length() != 64 or not sha.is_valid_hex_number(false) or referenced.has(sha):
			continue
		if DirAccess.remove_absolute(directory.path_join(filename)) != OK:
			error = "storage_error"
			return false
	return true


static func atomic_bytes(path: String, bytes_value: PackedByteArray) -> bool:
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes_value)
	file.flush()
	var success := file.get_error() == OK
	file.close()
	if not success or FileAccess.get_file_as_bytes(temporary) != bytes_value:
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return false
		if DirAccess.rename_absolute(path, backup) != OK:
			return false
	if DirAccess.rename_absolute(temporary, path) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return false
	return true
