extends SceneTree

var failures := 0
var location := ""


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)


func _run() -> void:
	location = OS.get_environment("TEMP").path_join("rs-cloud-test-" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(location)
	check(CloudTransport.valid_endpoint(CloudTransport.DEFAULT_ENDPOINT), "HTTPS service")
	check(CloudTransport.valid_endpoint("http://127.0.0.1:18763/api/cloud/v1"), "loopback injection")
	for endpoint in ["http://example.com/api", "http://127.0.0.1:80@evil.test", "https://user:pass@example.com", "https://example.com/#bad"]:
		check(not CloudTransport.valid_endpoint(endpoint), "endpoint restriction " + endpoint)
	var document: Sc2File = EmptyCityTemplate.create(16)
	var encoded := document.serialize(true)
	check(encoded.ok, "fixture encoded")
	var bytes: PackedByteArray = encoded.data.duplicate()
	var inspected := CloudSnapshot.inspect(bytes)
	check(inspected.ok, "valid snapshot")
	check(not inspected.metadata.has("path"), "metadata never contains local path")
	check(not CloudSnapshot.inspect(bytes, "0".repeat(64)).ok, "checksum verification")
	check(not CloudSnapshot.inspect(bytes, "", {"mods": [{"id": "unknown", "version": "1"}]}).ok, "missing gameplay mod rejected")
	check(not CloudSnapshot.inspect(bytes, "", {"game_version": "99.0.0"}).ok, "future game rejected")
	check(not CloudSnapshot.inspect(PackedByteArray([1, 2, 3])).ok, "malformed snapshot rejected")
	var queue := CloudQueue.new()
	check(queue.open(location, "endpoint|account-a"), "queue open")
	queue.state.bindings["city.sc2x"] = {"enabled": true, "revision": "r1", "save_id": "s1"}
	var added := queue.enqueue("city.sc2x", bytes, inspected.metadata)
	check(added.ok and queue.state.jobs.size() == 1, "durable immutable snapshot")
	bytes[0] = 0
	check(queue.bytes(queue.state.jobs[0]) == encoded.data, "caller mutation does not change snapshot")
	var restarted := CloudQueue.new()
	check(restarted.open(location, "endpoint|account-a") and restarted.state.jobs.size() == 1, "restart replays pending")
	check(restarted.bytes(restarted.state.jobs[0]) == encoded.data, "restart blob integrity")
	var other := CloudQueue.new()
	check(other.open(location, "endpoint|account-b") and other.state.jobs.is_empty(), "account isolation")
	check(other.directory != restarted.directory, "account directories separate")
	var path := queue.directory.path_join("queue.json")
	DirAccess.rename_absolute(path, path + ".bak")
	var interrupted := CloudQueue.new()
	check(interrupted.open(location, "endpoint|account-a") and interrupted.state.jobs.size() == 1, "interrupted manifest replacement recovers")
	await _test_sync(encoded.data)
	_test_complete_units()
	_test_bounded_cache()
	print("Cloud sync tests: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _test_bounded_cache() -> void:
	var queue := RefusingQueue.new()
	check(queue.open(location.path_join("bounded"), "account"), "bounded cache fixture")
	var original := location.path_join("never-delete-original.sc2x")
	CloudQueue.atomic_bytes(original, "original local city".to_utf8_buffer())
	queue.state.bindings[original] = {"enabled": true}
	for index in 8:
		check(queue.enqueue(original, ("version " + str(index)).to_utf8_buffer(), {"name": "City"}).ok, "cache version queued")
		queue.state.jobs[-1].status = "done"
	var first_hash: String = queue.state.jobs[0].sha256
	var second_hash: String = queue.state.jobs[1].sha256
	var removed_hash: String = queue.state.jobs[2].sha256
	# Two other paths share old completed content, but remain unresolved.
	queue.state.bindings["pending"] = {"enabled": true}
	queue.state.bindings["conflict"] = {"enabled": true}
	queue.enqueue("pending", "version 0".to_utf8_buffer(), {"name": "Pending"})
	queue.enqueue("conflict", "version 1".to_utf8_buffer(), {"name": "Conflict"})
	queue.state.jobs[-1].status = "conflict"
	queue.persist()
	var before: Array = queue.state.jobs.duplicate(true)
	queue.refuse = true
	check(not queue.prune_completed(), "failed manifest prune reported")
	check(queue.state.jobs == before, "failed prune rolls back memory manifest")
	check(FileAccess.file_exists(queue.directory.path_join(removed_hash + ".save")), "failed persistence never collects blobs")
	queue.refuse = false
	check(queue.prune_completed(), "bounded completed history pruned")
	check(queue.state.jobs.size() == 7, "five completed plus all unresolved snapshots kept")
	check(FileAccess.file_exists(queue.directory.path_join(first_hash + ".save")), "shared pending hash protected")
	check(FileAccess.file_exists(queue.directory.path_join(second_hash + ".save")), "shared conflict hash protected")
	check(not FileAccess.file_exists(queue.directory.path_join(removed_hash + ".save")), "unreferenced old completed blob removed")
	check(FileAccess.get_file_as_string(original) == "original local city", "original path never touched")
	var reopened := CloudQueue.new()
	check(reopened.open(location.path_join("bounded"), "account") and reopened.state.jobs.size() == 7, "bounded manifest durable after restart")
	for job: Dictionary in reopened.state.jobs:
		check(not reopened.bytes(job).is_empty(), "all durable references still resolve")
	# Retained and retry branches also protect shared blobs regardless of age.
	queue.state.jobs[-1].status = "retained"
	queue.state.jobs[-2].status = "retry"
	queue.persist()
	check(queue.prune_completed() and queue.state.jobs.size() == 7, "retained and retry branches never collected")


func _test_complete_units() -> void:
	var document: Sc2File = Sc2xDocument.create_empty(32, "Whole region").document
	var campaign := RegionCampaign.new()
	check(campaign.initialize_at(document, 2, 123, "solo", Vector2i.ZERO).is_empty(), "region fixture")
	var child := document.duplicate_document(true)
	child.set_city_name("Second city")
	campaign.documents["1,0"] = child
	campaign.owners["1,0"] = "solo"
	campaign.acquired["1,0"] = campaign.current_day
	campaign.settled["1,0"] = campaign.current_day
	check(campaign.pack(document).is_empty(), "region packaged atomically")
	var encoded := document.serialize(true)
	var inspected := CloudSnapshot.inspect(encoded.data)
	check(inspected.ok and inspected.metadata.kind == "region", "whole region accepted as one blob")
	var corrupted := document.duplicate_document(true)
	corrupted.sc2x_extra_entries.erase(RegionCampaign.PREFIX + "1-0.sc2x")
	check(not CloudSnapshot.inspect(corrupted.serialize(true).data).ok, "missing regional city blocked")
	child.sc2x_metadata.required_features.append("future-gameplay")
	check(campaign.pack(document).is_empty(), "unknown child feature serialized losslessly")
	check(CloudSnapshot.inspect(document.serialize(true).data).get("error") == "incompatible_save", "inactive regional required feature rejected")
	child.sc2x_metadata.required_features.clear()
	child.sc2x_metadata.phase_state["active_disaster_type"] = "invalid"
	# Native metadata encoding can reject this before cloud validation, too.
	var packed_error := campaign.pack(document)
	check(not packed_error.is_empty() or not CloudSnapshot.inspect(document.serialize(true).data).ok, "inactive malformed checkpoint rejected")
	# Build a complete host checkpoint without sockets, profile credentials or
	# a live multiplayer session. The same reader validates every nested field.
	var session := CoopSession.new()
	session.world = CoopWorld.new()
	check(session.world.open(Sc2xDocument.create_empty(32, "Host checkpoint").document), "multiplayer fixture")
	session.hosting = true
	session.credential = "a".repeat(48)
	session.token = session.credential
	session.session_id = "b".repeat(32)
	session.members[session.token] = {"name": "Host", "sequence": 0, "color": "46b4ff", "seat_status": "connected"}
	session.seats.credentials[session.credential.sha256_text()] = session.token
	var checkpoint := session.city_checkpoint()
	check(checkpoint.error.is_empty(), "host checkpoint captured")
	var mp_bytes: PackedByteArray = checkpoint.document.serialize(true).data
	var before: PackedByteArray = mp_bytes.duplicate()
	var mp_checked := CloudSnapshot.inspect(mp_bytes)
	check(mp_checked.ok and mp_checked.metadata.kind == "multiplayer", "full multiplayer checkpoint validated")
	check(mp_bytes == before and session.credential == "a".repeat(48), "validation does not transfer live seat or mutate source")
	var data: Dictionary = JSON.parse_string(checkpoint.document.sc2x_extra_entries["multiplayer.json"].get_string_from_utf8())
	data.dispatch = [0]
	checkpoint.document.sc2x_extra_entries["multiplayer.json"] = JSON.stringify(data).to_utf8_buffer()
	check(not CloudSnapshot.inspect(checkpoint.document.serialize(true).data).ok, "malformed multiplayer checkpoint blocked")
	var sync := CloudSync.new()
	root.add_child(sync)
	sync.configure(location.path_join("host-gate"))
	sync.queue = CloudQueue.new()
	check(sync.queue.open(location.path_join("host-gate"), "account"), "host authority queue")
	var path := location.path_join("host.sc2x")
	sync.set_enabled(path, true)
	check(sync.saved(path, mp_bytes).get("error") == "host_only", "nonhost full checkpoint rejected")
	check(sync.queue.state.jobs.is_empty(), "nonhost never reaches durable upload queue")
	check(sync.saved(path, mp_bytes, {"host_authorized": true}).ok, "host may enqueue complete session")
	sync.free()
	session.free()


func _test_sync(bytes: PackedByteArray) -> void:
	var sync := CloudSync.new()
	root.add_child(sync)
	sync.configure(location.path_join("sync"), "http://127.0.0.1:18763/api/cloud/v1")
	sync.transport.free()
	var fake := FakeTransport.new()
	sync.transport = fake
	sync.add_child(fake)
	fake.token = "test-token"
	sync.account = {"id": "a", "email": "a@example.test"}
	sync.queue = CloudQueue.new()
	check(sync.queue.open(location.path_join("sync"), "a"), "sync queue")
	var target := sync._local_path(location.path_join("local.sc2x"))
	check(sync.set_enabled(target, true).ok, "explicit opt-in")
	fake.offline = true
	check(sync.saved(target, bytes).ok, "offline queue does not block local save")
	await sync.pump()
	check(sync.queue.state.jobs[0].status == "retry", "offline preserves pending job")
	fake.offline = false
	await sync.pump()
	check(sync.queue.state.jobs[0].status == "done", "retry uploads successfully")
	check(sync.queue.state.bindings[target].revision == "r1", "revision recorded")
	check(fake.uploaded == bytes, "immutable uploaded bytes exact")
	check(sync.saved(target, bytes).get("skipped", false), "unchanged manual save deduplicated")
	var changed_document := Sc2File.new()
	changed_document.parse(bytes)
	changed_document.set_city_name("New branch")
	var changed_bytes := changed_document.serialize(true).data
	fake.conflict = true
	check(sync.saved(target, changed_bytes).ok, "second revision queued")
	await sync.pump()
	check(sync.snapshot().conflicts.size() == 1, "remote edit retained as conflict")
	check(sync.queue.bytes(sync.queue.state.jobs[1]) == changed_bytes, "conflict local copy retained")
	var job_id: String = sync.queue.state.jobs[1].id
	check(sync.resolve_conflict(job_id, "both").ok, "explicit both branches")
	fake.conflict = false
	await sync.pump()
	check(fake.created == 2, "both creates independent cloud save")
	check(sync.queue.state.jobs[1].status == "done", "fork committed")
	fake.download_bytes = bytes
	var destination := location.path_join("download.sc2x")
	check((await sync.download("s1", "r1", destination)).ok, "download verifies and atomically writes")
	check(FileAccess.get_file_as_bytes(destination) == bytes, "download byte identity")
	check(not (await sync.download("s1", "r1", destination)).ok, "existing local branch not overwritten")
	fake.corrupt_download = true
	check(not (await sync.download("s1", "r1", location.path_join("bad.sc2x"))).ok, "corrupt download blocked")
	check(not FileAccess.file_exists(location.path_join("bad.sc2x")), "bad download not installed")
	changed_document.set_city_name("Expired upload")
	var expiration_bytes := changed_document.serialize(true).data
	check(sync.saved(target, expiration_bytes).ok, "expired staging snapshot queued")
	var expired: Dictionary = sync.queue.state.jobs[-1]
	expired.upload_id = "expired"
	sync.queue.persist()
	var reopened := CloudQueue.new()
	check(reopened.open(location.path_join("sync"), "a"), "durable pending upload reopens")
	sync.queue = reopened
	await sync.pump()
	check(sync.queue.state.jobs[-1].status == "done", "expired upload restarts with same base")
	check(fake.expired_requests == 1, "old staging actually requested once")
	sync.free()


class FakeTransport extends CloudTransport:
	var offline := false
	var conflict := false
	var created := 0
	var uploaded := PackedByteArray()
	var download_bytes := PackedByteArray()
	var corrupt_download := false
	var upload_id := 0
	var sha := ""
	var expired_requests := 0

	func request(method: int, route: String, body: Variant = null, binary := false) -> Dictionary:
		if offline:
			return {"ok": false, "error": "offline", "code": 0}
		if route == "/saves" and method == HTTPClient.METHOD_POST:
			created += 1
			return {"ok": true, "id": "s" + str(created)}
		if route.ends_with("/uploads"):
			upload_id += 1
			sha = body.sha256
			return {"ok": true, "id": "u" + str(upload_id), "chunk_size": 1048576, "chunks": []}
		if route.ends_with("/uploads/expired"):
			expired_requests += 1
			return {"ok": false, "error": "not_found", "code": 404}
		if route.contains("/chunks/"):
			uploaded = body.duplicate()
			return {"ok": true}
		if route.ends_with("/commit"):
			return {"ok": false, "code": 409, "error": "conflict", "head": "remote"} if conflict else {"ok": true, "revision": "r1", "sha256": sha}
		if route.ends_with("/versions"):
			return {"ok": true, "versions": [{"revision": "r1", "size": download_bytes.size(), "sha256": CloudSnapshot.digest(download_bytes), "metadata": {}}]}
		if binary:
			return {"ok": true, "bytes": PackedByteArray([0]) if corrupt_download else download_bytes}
		return {"ok": false, "error": "invalid_request", "code": 400}


class RefusingQueue extends CloudQueue:
	var refuse := false

	func persist() -> bool:
		return false if refuse else super.persist()
