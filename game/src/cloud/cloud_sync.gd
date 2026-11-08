# gdstyle:ignore-file=quality/max-public-methods
class_name CloudSync
extends Node
## Local-first synchronization. Local saves never wait for a network request.
## Each queued version retains the server predecessor observed when it was made.

signal changed
const RETRY_SECONDS := 300.0
var transport: CloudTransport
var queue: CloudQueue
var root_path := ""
var account: Dictionary = {}
var device_id := ""
var remember := false
var saves: Array = []
var devices: Array = []
var usage := {"used_bytes": 0, "quota_bytes": 0}
var status := "signed_out"
var error := ""
var _elapsed := 0.0
var _pumping := false
var _epoch := 0
var _account_key := ""


func configure(storage_path := "", endpoint := CloudTransport.DEFAULT_ENDPOINT) -> void:
	root_path = storage_path if not storage_path.is_empty() else AppPaths.path("cloud")
	transport = CloudTransport.new()
	transport.endpoint = endpoint
	add_child(transport)


func start() -> void:
	if transport == null:
		configure()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(root_path.path_join("account.json"))) if FileAccess.file_exists(root_path.path_join("account.json")) else null
	if not data is Dictionary or data.get("endpoint") != transport.endpoint or not data.get("account") is Dictionary:
		return
	account = data.account
	_account_key = _key(str(account.get("id", "")))
	var credential := CloudCredentialStore.load_token(_account_key)
	if not credential.ok or str(credential.get("token", "")).is_empty():
		account = {}
		return
	remember = true
	transport.token = credential.token
	device_id = str(data.get("device_id", ""))
	if not _open_queue():
		return
	status = "offline"
	changed.emit()
	await refresh()
	pump()


func snapshot() -> Dictionary:
	var jobs: Array = [] if queue == null else queue.state.jobs.duplicate(true)
	var conflicts: Array = []
	for job: Dictionary in jobs:
		if job.status == "conflict":
			conflicts.append({"id": job.id, "name": job.metadata.get("name", ""), "path": job.path,
				"cloud_revision": job.get("cloud_revision", "")})
	return {"account": account.duplicate(true), "remember": remember, "busy": _pumping,
		"status": status, "error": error, "saves": saves.duplicate(true), "devices": devices.duplicate(true),
		"usage": usage.duplicate(), "queue": jobs, "conflicts": conflicts}


func register(email: String, password: String) -> Dictionary:
	return _report(await transport.request(HTTPClient.METHOD_POST, "/register", {"email": email, "password": password}))


func verify(email: String, code: String) -> Dictionary:
	return _report(await transport.request(HTTPClient.METHOD_POST, "/verify", {"email": email, "code": code}))


func request_reset(email: String) -> Dictionary:
	return _report(await transport.request(HTTPClient.METHOD_POST, "/reset-request", {"email": email}))


func reset_password(email: String, code: String, password: String) -> Dictionary:
	return _report(await transport.request(HTTPClient.METHOD_POST, "/reset", {"email": email, "code": code, "password": password}))


func login(email: String, password: String, keep_signed_in: bool) -> Dictionary:
	if not account.is_empty():
		return _report({"ok": false, "error": "already_signed_in"})
	var result := await transport.request(HTTPClient.METHOD_POST, "/login", {"email": email,
		"password": password, "device": OS.get_name() + " — Reticulating Splines"})
	if not result.ok:
		return _report(result)
	if not result.get("account") is Dictionary or not result.get("token") is String or not result.get("device_id") is String:
		return _report({"ok": false, "error": "invalid_response"})
	_epoch += 1
	account = result.account
	device_id = result.device_id
	transport.token = result.token
	_account_key = _key(str(account.get("id", "")))
	remember = keep_signed_in
	if not _open_queue():
		return _report({"ok": false, "error": "storage_error"})
	var stored := _remember_account()
	if not stored.ok:
		remember = false
	status = "connected"
	await refresh()
	pump()
	# Never pass a bearer credential to presentation code.
	return _report(stored)


func set_remember(enabled: bool) -> Dictionary:
	if account.is_empty():
		return _report({"ok": false, "error": "unauthorized"})
	if enabled == remember:
		return {"ok": true, "error": ""}
	# Stop continuations using the old token before the server revokes it.
	_epoch += 1
	var epoch := _epoch
	var result := await transport.request(HTTPClient.METHOD_POST, "/session/rotate", {})
	if epoch != _epoch:
		return {"ok": false, "error": "cancelled"}
	if not result.ok:
		return _report(result)
	transport.token = str(result.get("token", ""))
	remember = enabled
	CloudCredentialStore.delete(_account_key)
	return _report(_remember_account())


func logout() -> Dictionary:
	# A failed remote revocation is visible; never claim the device was revoked.
	_epoch += 1
	var result := await transport.request(HTTPClient.METHOD_DELETE, "/devices/" + device_id.uri_encode()) if not device_id.is_empty() else {"ok": true, "error": ""}
	if not result.ok and result.get("code") != 401:
		return _report(result)
	_clear_session()
	return _report({"ok": true, "error": ""})


func _clear_session() -> void:
	_epoch += 1
	CloudCredentialStore.delete(_account_key)
	CloudQueue.atomic_bytes(root_path.path_join("account.json"), "{}".to_utf8_buffer())
	transport.token = ""
	account = {}
	device_id = ""
	remember = false
	queue = null
	saves = []
	devices = []
	usage = {"used_bytes": 0, "quota_bytes": 0}
	status = "signed_out"


func refresh() -> Dictionary:
	if account.is_empty():
		return _report({"ok": false, "error": "unauthorized"})
	var epoch := _epoch
	var me := await transport.request(HTTPClient.METHOD_GET, "/me")
	if epoch != _epoch:
		return {"ok": false, "error": "cancelled"}
	if not me.ok:
		status = "offline" if me.get("code", 0) == 0 else "signed_out" if me.get("code") == 401 else "error"
		if me.get("code") == 401:
			_clear_session()
		return _report(me)
	usage = {"used_bytes": me.get("usage", 0), "quota_bytes": me.get("quota", 0)}
	var active := await transport.request(HTTPClient.METHOD_GET, "/saves")
	var deleted := await transport.request(HTTPClient.METHOD_GET, "/saves?trash=1")
	var device_list := await transport.request(HTTPClient.METHOD_GET, "/devices")
	if epoch != _epoch:
		return {"ok": false, "error": "cancelled"}
	if active.ok and deleted.ok:
		saves = active.get("saves", []) + deleted.get("saves", [])
	if device_list.ok:
		devices = device_list.get("devices", [])
	status = "connected"
	return _report(active if not active.ok else deleted if not deleted.ok else device_list)


func list_versions(save_id: String) -> Dictionary:
	return _report(await transport.request(HTTPClient.METHOD_GET, "/saves/" + save_id.uri_encode() + "/versions"))


func trash(save_id: String) -> Dictionary:
	return await _mutate(HTTPClient.METHOD_DELETE, "/saves/" + save_id.uri_encode())


func undelete(save_id: String) -> Dictionary:
	return await _mutate(HTTPClient.METHOD_POST, "/saves/" + save_id.uri_encode() + "/undelete", {})


func restore_version(save_id: String, revision: String, base_revision: Variant) -> Dictionary:
	return await _mutate(HTTPClient.METHOD_POST, "/saves/" + save_id.uri_encode() + "/restore", {"revision": revision, "base_revision": base_revision})


func revoke_device(id: String) -> Dictionary:
	if id == device_id:
		return await logout()
	return await _mutate(HTTPClient.METHOD_DELETE, "/devices/" + id.uri_encode())


func set_enabled(path: String, enabled: bool) -> Dictionary:
	if queue == null:
		return _report({"ok": false, "error": "unauthorized"})
	path = _local_path(path)
	var old: Dictionary = queue.state.bindings.get(path, {}).duplicate(true)
	var binding: Dictionary = old.duplicate(true)
	binding["enabled"] = enabled
	queue.state.bindings[path] = binding
	if not queue.persist():
		queue.state.bindings[path] = old
		return _report({"ok": false, "error": "storage_error"})
	return _report({"ok": true, "error": ""})


func is_enabled(path: String) -> bool:
	return queue != null and queue.state.bindings.get(_local_path(path), {}).get("enabled", false)


## -1 means the account's current availability cannot be established locally.
func local_availability(path: String) -> int:
	if account.is_empty() or queue == null:
		return -1
	var binding: Dictionary = queue.state.bindings.get(_local_path(path), {})
	var save_id := str(binding.get("save_id", ""))
	if status == "connected":
		for save: Dictionary in saves:
			if str(save.get("id", "")) == save_id and save.get("deleted_at") == null:
				return 1
		return 0
	return 1 if not save_id.is_empty() and not str(binding.get("revision", "")).is_empty() else -1


func saved(path: String, bytes: PackedByteArray, metadata: Dictionary = {}) -> Dictionary:
	path = _local_path(path)
	if not is_enabled(path):
		return {"ok": true, "skipped": true}
	var checked := CloudSnapshot.inspect(bytes)
	if not checked.ok:
		return _report(checked)
	if checked.metadata.kind == "multiplayer" and not metadata.get("host_authorized", false):
		return _report({"ok": false, "error": "host_only"})
	var result := queue.enqueue(path, bytes.duplicate(), checked.metadata)
	changed.emit()
	if result.ok:
		pump.call_deferred()
	return result


func download(save_id: String, revision: String, path: String) -> Dictionary:
	var epoch := _epoch
	var versions := await list_versions(save_id)
	if not versions.ok:
		return versions
	var version: Dictionary = {}
	for item: Dictionary in versions.get("versions", []):
		if item.get("revision") == revision:
			version = item
	if version.is_empty():
		return _report({"ok": false, "error": "not_found"})
	if not version.get("metadata", {}) is Dictionary:
		return _report({"ok": false, "error": "invalid_response"})
	if not version.get("sha256") is String or version.sha256.length() != 64 or not version.sha256.is_valid_hex_number(false):
		return _report({"ok": false, "error": "invalid_response"})
	var response := await transport.request(HTTPClient.METHOD_GET,
		"/saves/" + save_id.uri_encode() + "/versions/" + revision.uri_encode() + "/content", null, true)
	if epoch != _epoch:
		return {"ok": false, "error": "cancelled"}
	if not response.ok:
		return _report(response)
	if response.bytes.size() != int(version.get("size", -1)):
		return _report({"ok": false, "error": "checksum_mismatch"})
	var checked := CloudSnapshot.inspect(response.bytes, str(version.get("sha256", "")), version.get("metadata", {}))
	if not checked.ok:
		return _report(checked)
	# Explicit download is a new copy. Never silently overwrite a local branch.
	if FileAccess.file_exists(path):
		return _report({"ok": false, "error": "target_exists"})
	var result := CityFileStore.write_verified(path, response.bytes)
	if not result.ok:
		return _report({"ok": false, "error": "storage_error"})
	if queue != null:
		queue.state.bindings[_local_path(path)] = {"enabled": true, "save_id": save_id,
			"revision": revision, "last_sha256": version.sha256}
		if not queue.persist():
			return _report({"ok": false, "error": "storage_error", "path": path})
	return _report({"ok": true, "error": "", "path": path})


func resolve_conflict(job_id: String, choice: String) -> Dictionary:
	if queue == null or choice not in ["cloud", "local", "both"]:
		return _report({"ok": false, "error": "invalid_request"})
	for job: Dictionary in queue.state.jobs:
		if job.id != job_id or job.status != "conflict":
			continue
		if choice == "cloud":
			# Keep the local immutable blob and file; stop this branch's uploads.
			job.status = "retained"
			queue.state.bindings[job.path].enabled = false
		elif choice == "both":
			job.save_id = ""
			job.base_revision = null
			job.upload_id = ""
			job.metadata.name = str(job.metadata.name) + " (copy)"
			job.status = "queued"
		else:
			# Explicitly promote local as a new version based on the shown head.
			job.base_revision = job.cloud_revision
			job.upload_id = ""
			job.status = "queued"
		if not queue.persist():
			return _report({"ok": false, "error": "storage_error"})
		changed.emit()
		pump.call_deferred()
		return {"ok": true, "error": ""}
	return _report({"ok": false, "error": "not_found"})


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= RETRY_SECONDS:
		_elapsed = 0.0
		pump()


func pump() -> void:
	if _pumping or queue == null or transport.token.is_empty():
		return
	_pumping = true
	var epoch := _epoch
	var current := queue
	for job: Dictionary in current.state.jobs.duplicate():
		if epoch != _epoch:
			break
		if job.status not in ["queued", "retry", "uploading"] or not current.state.bindings.get(job.path, {}).get("enabled", false):
			continue
		var blocked := false
		for earlier: Dictionary in current.state.jobs:
			if earlier.id == job.id:
				break
			if earlier.path == job.path and earlier.status != "done":
				blocked = true
		if blocked:
			continue
		var result := await _upload(current, job, epoch)
		if epoch != _epoch:
			break
		if not result.ok:
			job.status = "conflict" if result.get("code") == 409 else "retry"
			job.error = result.get("error", "request_failed")
			if job.status == "conflict":
				job["cloud_revision"] = result.get("head")
			status = "offline" if result.get("code", 0) == 0 else job.status
			error = job.error
			current.persist()
			if result.get("code") == 401:
				_clear_session()
			break
		job.status = "done"
		var binding: Dictionary = current.state.bindings[job.path]
		binding.merge({"save_id": job.save_id, "revision": result.revision, "last_sha256": job.sha256}, true)
		# Later local snapshots share this exact predecessor chain, never a
		# revision from an independently changed remote branch.
		for later: Dictionary in current.state.jobs:
			if later.path == job.path and later.status in ["queued", "retry"] and later.upload_id.is_empty():
				later.save_id = job.save_id
				later.base_revision = result.revision
		if not current.persist():
			error = "storage_error"
			break
		if not current.prune_completed():
			error = "storage_error"
			break
		status = "connected"
		error = ""
		changed.emit()
	_pumping = false
	changed.emit()


func _upload(current: CloudQueue, job: Dictionary, epoch: int) -> Dictionary:
	var bytes := current.bytes(job)
	if bytes.is_empty():
		return {"ok": false, "error": "checksum_mismatch"}
	job.status = "uploading"
	if job.save_id.is_empty():
		var created := await transport.request(HTTPClient.METHOD_POST, "/saves", {"name": job.metadata.name,
			"kind": job.metadata.kind, "metadata": job.metadata, "client_id": job.id})
		if epoch != _epoch:
			return {"ok": false, "error": "cancelled"}
		if not created.ok:
			return created
		job.save_id = str(created.get("id", ""))
		if job.save_id.is_empty() or not current.persist():
			return {"ok": false, "error": "storage_error"}
	var base := "/saves/" + str(job.save_id).uri_encode() + "/uploads"
	var upload: Dictionary
	if job.upload_id.is_empty():
		upload = await transport.request(HTTPClient.METHOD_POST, base, {"base_revision": job.base_revision,
			"size": job.size, "sha256": job.sha256, "metadata": job.metadata})
	else:
		upload = await transport.request(HTTPClient.METHOD_GET, base + "/" + str(job.upload_id).uri_encode())
		if upload.get("code") in [404, 410]:
			job.upload_id = ""
			if current.persist():
				return await _upload(current, job, epoch)
	if epoch != _epoch:
		return {"ok": false, "error": "cancelled"}
	if not upload.ok:
		return upload
	job.upload_id = str(upload.get("id", ""))
	var chunk_size := int(upload.get("chunk_size", 1048576))
	if job.upload_id.is_empty() or chunk_size < 65536 or chunk_size > 4 * 1048576 or not upload.get("chunks", []) is Array:
		return {"ok": false, "error": "invalid_response"}
	if not current.persist():
		return {"ok": false, "error": "storage_error"}
	base += "/" + str(job.upload_id).uri_encode()
	if upload.get("revision") != null:
		return await transport.request(HTTPClient.METHOD_POST, base + "/commit", {})
	for offset in range(0, bytes.size(), chunk_size):
		@warning_ignore("integer_division")
		var index := offset / chunk_size
		if index in upload.get("chunks", []):
			continue
		var written := await transport.request(HTTPClient.METHOD_PUT, base + "/chunks/" + str(index), bytes.slice(offset, offset + chunk_size))
		if epoch != _epoch:
			return {"ok": false, "error": "cancelled"}
		if not written.ok:
			return written
	var committed := await transport.request(HTTPClient.METHOD_POST, base + "/commit", {})
	if committed.ok and (committed.get("sha256") != job.sha256 or not committed.get("revision") is String):
		return {"ok": false, "error": "invalid_response"}
	return committed


func _open_queue() -> bool:
	queue = CloudQueue.new()
	if not queue.open(root_path, transport.endpoint + "|" + str(account.get("id", ""))):
		error = queue.error
		queue = null
		changed.emit()
		return false
	return true


func _remember_account() -> Dictionary:
	if not remember:
		CloudCredentialStore.delete(_account_key)
		CloudQueue.atomic_bytes(root_path.path_join("account.json"), "{}".to_utf8_buffer())
		return {"ok": true, "error": ""}
	var stored := CloudCredentialStore.store(_account_key, transport.token)
	if not stored.ok:
		remember = false
		return {"ok": false, "error": "credential_unavailable"}
	if not CloudQueue.atomic_bytes(root_path.path_join("account.json"), JSON.stringify({"endpoint": transport.endpoint,
		"account": account, "device_id": device_id}).to_utf8_buffer()):
		CloudCredentialStore.delete(_account_key)
		remember = false
		return {"ok": false, "error": "storage_error"}
	return {"ok": true, "error": ""}


func _key(id: String) -> String:
	return (transport.endpoint + "|" + id + "|" + _local_path(root_path)).sha256_text()


func _local_path(path: String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path()


func _report(result: Dictionary) -> Dictionary:
	error = str(result.get("error", ""))
	changed.emit()
	return result


func _mutate(method: int, route: String, body: Variant = null) -> Dictionary:
	var epoch := _epoch
	var result := await transport.request(method, route, body)
	if epoch != _epoch:
		return {"ok": false, "error": "cancelled"}
	if result.get("code") == 401:
		_clear_session()
	if result.ok:
		await refresh()
	return _report(result)
