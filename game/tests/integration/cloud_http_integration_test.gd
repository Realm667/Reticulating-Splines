extends SceneTree
## Requires the disposable PHP service and private mail-spool fixture described
## in server/cloud/README.md. Never points at the production service.

var failures := 0
var directory := ""
var endpoint := ""


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)


func make_client(folder: String) -> CloudSync:
	var sync := CloudSync.new()
	root.add_child(sync)
	sync.configure(directory.path_join(folder), endpoint)
	return sync


func run() -> void:
	directory = OS.get_environment("RS_CLOUD_TEST_DIRECTORY")
	endpoint = OS.get_environment("RS_CLOUD_TEST_ENDPOINT")
	if directory.is_empty() or not endpoint.begins_with("http://127.0.0.1:"):
		push_error("Cloud HTTP integration requires an isolated loopback fixture.")
		quit(1)
		return
	var email := "client-" + str(Time.get_ticks_usec()) + "@example.test"
	var password := Crypto.new().generate_random_bytes(18).hex_encode()
	var first := make_client("device-a-" + str(Time.get_ticks_usec()))
	check((await first.register(email, password)).ok, "register")
	var code := FileAccess.get_file_as_string(directory.path_join((email + ":verify").sha256_text() + ".code"))
	check(code.length() == 8, "in-game email code")
	check((await first.verify(email, code)).ok, "verify")
	check((await first.login(email, password, false)).ok, "login without remembering")
	if first.account.is_empty():
		first.free()
		quit(1)
		return
	check(not FileAccess.get_file_as_string(first.root_path.path_join("account.json")).contains(first.transport.token), "token never in local settings")
	var document: Sc2File = Sc2xDocument.create_empty(16, "Cloud HTTP").document
	document.sc2x_extra_entries["cloud-test.bin"] = Crypto.new().generate_random_bytes(2 * 1048576 + 123)
	var encoded := document.serialize(true)
	var local_path := directory.path_join("original-" + email.get_slice("@", 0) + ".sc2x")
	check(CityFileStore.write_verified(local_path, encoded.data).ok, "local save succeeds first")
	check(first.set_enabled(local_path, true).ok, "opt in")
	var inspected := CloudSnapshot.inspect(encoded.data)
	check(first.queue.enqueue(first._local_path(local_path), encoded.data, inspected.metadata).ok, "enqueue")
	var staged: Dictionary = first.queue.state.jobs[0]
	var created := await first.transport.request(HTTPClient.METHOD_POST, "/saves", {"name": inspected.metadata.name,
		"kind": "city", "metadata": inspected.metadata, "client_id": staged.id})
	check(created.ok, "create upload target")
	staged.save_id = created.id
	var upload := await first.transport.request(HTTPClient.METHOD_POST, "/saves/" + str(created.id) + "/uploads", {
		"base_revision": null, "size": encoded.data.size(), "sha256": staged.sha256, "metadata": staged.metadata})
	check(upload.ok, "begin resumable upload")
	staged.upload_id = upload.id
	check((await first.transport.request(HTTPClient.METHOD_PUT, "/saves/" + str(created.id) + "/uploads/" + str(upload.id) + "/chunks/0", encoded.data.slice(0, 1048576))).ok, "first chunk before interruption")
	first.queue.persist()
	var reopened := CloudQueue.new()
	check(reopened.open(first.root_path, first.transport.endpoint + "|" + str(first.account.id)), "queue reload before partial resume")
	first.queue = reopened
	await first.pump()
	check(first.queue.state.jobs[0].status == "done", "real chunk upload commits")
	if first.queue.state.jobs[0].status != "done":
		printerr("Cloud test service error: " + first.error)
		first.free()
		quit(1)
		return
	var binding: Dictionary = first.queue.state.bindings[first._local_path(local_path)]
	var save_id: String = binding.save_id
	var original_revision: String = binding.revision
	var second := make_client("device-b-" + str(Time.get_ticks_usec()))
	check((await second.login(email, password, false)).ok, "second device login")
	check(second.saves.size() == 1, "save visible on second device")
	var second_path := directory.path_join("second-" + email.get_slice("@", 0) + ".sc2x")
	check((await second.download(save_id, original_revision, second_path)).ok, "second device downloads verified copy")
	check(FileAccess.get_file_as_bytes(second_path) == encoded.data, "download matches original exact bytes")
	document.set_city_name("First device branch")
	var branch_a := document.serialize(true).data
	first.saved(local_path, branch_a)
	await first.pump()
	document.set_city_name("Second device branch")
	var branch_b := document.serialize(true).data
	second.saved(second_path, branch_b)
	await second.pump()
	check(second.snapshot().conflicts.size() == 1, "parallel continuation conflicts")
	var conflict_job: Dictionary = second.queue.state.jobs[-1]
	check(second.queue.bytes(conflict_job) == branch_b, "conflict local snapshot retained")
	check(second.resolve_conflict(conflict_job.id, "both").ok, "keep both requested")
	await second.pump()
	await second.refresh()
	check(second.saves.size() == 2, "both branches independently listed")
	await first.refresh()
	var current_head: String = first.queue.state.bindings[first._local_path(local_path)].revision
	check((await first.restore_version(save_id, original_revision, current_head)).ok, "version restore uses optimistic head")
	check((await first.trash(save_id)).ok, "trash")
	check(first.saves.any(func(item: Dictionary) -> bool: return item.id == save_id and item.deleted_at != null), "trash listed")
	check((await first.undelete(save_id)).ok, "restore from trash")
	# Revocation removes only this device; the other retains its independent token.
	check((await first.revoke_device(second.device_id)).ok, "revoke second device")
	check(not (await second.refresh()).ok and second.account.is_empty(), "revoked session enters sign-in state")
	check((await first.request_reset(email)).ok, "request password reset")
	code = FileAccess.get_file_as_string(directory.path_join((email + ":reset").sha256_text() + ".code"))
	var next_password := Crypto.new().generate_random_bytes(18).hex_encode()
	check((await first.reset_password(email, code, next_password)).ok, "password reset in game")
	check(not (await first.refresh()).ok and first.account.is_empty(), "reset revokes old session")
	check((await first.login(email, next_password, false)).ok, "new password login")
	check((await first.logout()).ok and first.account.is_empty(), "logout revokes session")
	first.queue_free()
	second.queue_free()
	await process_frame
	print("Cloud HTTP integration: %d failure(s)" % failures)
	quit(1 if failures else 0)
