extends SceneTree

const WindowScript = preload("res://src/ui/cloud/cloud_window.gd")

class FakeCloud extends Node:
	signal changed
	var calls: Array = []
	var enabled := false
	var data := {"account": {}, "busy": false, "error": "", "saves": [], "devices": [], "usage": {}, "queue": [], "conflicts": []}

	func snapshot() -> Dictionary:
		return data.duplicate(true)

	func is_enabled(_path: String) -> bool:
		return enabled

	func set_enabled(path: String, value: bool) -> Dictionary:
		calls.append(["enabled", path, value])
		enabled = value
		return {"ok": true}

	func login(address: String, secret: String, remember: bool) -> Dictionary:
		calls.append(["login", address, secret, remember])
		return {"ok": true}

	func register(address: String, secret: String) -> Dictionary:
		calls.append(["register", address, secret])
		return {"ok": true}

	func verify(address: String, challenge: String) -> Dictionary:
		calls.append(["verify", address, challenge])
		return {"ok": true}

	func list_versions(id: String) -> Dictionary:
		calls.append(["versions", id])
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color.BLUE)
		return {"ok": true, "versions": [{"revision": "r1", "created_at": "2026-10-31", "device_name": "Test device",
			"metadata": {"preview": Marshalls.raw_to_base64(image.save_png_to_buffer())}}]}

	func resolve_conflict(id: String, choice: String) -> Dictionary:
		calls.append(["resolve", id, choice])
		return {"ok": true}

	func revoke_device(id: String) -> Dictionary:
		calls.append(["revoke", id])
		return {"ok": true}

	func refresh() -> Dictionary:
		return {"ok": true}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := FakeCloud.new()
	root.add_child(service)
	var window := WindowScript.new()
	root.add_child(window)
	window.bind(service)
	assert(window.account_form.visible and not window.account_info.visible)
	assert(window.cloud_enabled.disabled)
	window.email.text = " test@example.invalid "
	window.password.text = "private-example"
	window.remember.button_pressed = true
	await window._authenticate()
	assert(service.calls[-1] == ["login", "test@example.invalid", "private-example", true])
	assert(window.password.text.is_empty())
	window.auth_mode.select(1)
	window.password.text = "register-example"
	await window._authenticate()
	assert(window.auth_mode.selected == 2 and window.code.visible and not window.password.visible)
	window.code.text = "123456"
	await window._authenticate()
	assert(service.calls[-1] == ["verify", "test@example.invalid", "123456"])
	assert(window.auth_mode.selected == 0 and window.code.text.is_empty())
	service.data.account = {"email": "test@example.invalid"}
	service.data.saves = [
		{"id": "a", "head": "r1", "name": "City A", "deleted_at": null, "metadata": {"year": 1950, "population": 1200}},
		{"id": "b", "head": "r2", "name": "City B", "deleted_at": "2026-10-30", "metadata": {}},
	]
	service.data.devices = [{"id": "other", "name": "Another device", "current": false}]
	window.set_current_path("user://cloud-ui-test.sc2x")
	assert(not window.cloud_enabled.disabled and not window.account_form.visible)
	window.cloud_enabled.button_pressed = true
	assert(service.enabled)
	assert(window.saves.item_count == 1 and window.save_rows[0].id == "a")
	window.saves.select(0)
	await window._select_save(0)
	assert(window.selected_save == "a" and window._revision() == "r1")
	assert(window.details.text.contains("1950") and window.details.text.contains("1200"))
	assert(not window.actions.download.disabled)
	assert(window.preview.visible, "Preview loads from the selected version, not the bulk save list")
	window.deleted.button_pressed = true
	assert(window.saves.item_count == 1 and window.save_rows[0].id == "b")
	assert(window.selected_save.is_empty() and window._revision().is_empty() and window.actions.download.disabled)
	window._set_preview("not an image")
	assert(not window.preview.visible)
	service.data.conflicts = [{"id": "job", "name": "City A"}]
	window.refresh()
	assert(window.conflicts.get_child_count() == 3)
	window._confirm_conflict("job", "both")
	assert(not service.calls.any(func(call: Array) -> bool: return call[0] == "resolve"))
	window.confirm.confirmed.emit()
	assert(service.calls[-1] == ["resolve", "job", "both"])
	window.devices.select(0)
	window._confirm_revoke()
	assert(service.calls[-1][0] != "revoke")
	window.confirm.confirmed.emit()
	assert(service.calls[-1] == ["revoke", "other"])
	assert(WindowScript.error_message("server secret <script>") == "The Cloud request failed. Please try again.")
	var exited := [false]
	service.data.queue = [{"status": "done"}, {"status": "retained"}]
	window.confirm_exit(func() -> void: exited[0] = true)
	assert(exited[0])
	exited[0] = false
	service.data.queue = [{"status": "retry"}]
	window.confirm_exit(func() -> void: exited[0] = true)
	assert(not exited[0])
	window.confirm.confirmed.emit()
	assert(exited[0])
	root.size = Vector2i(420, 600)
	window.open()
	await process_frame
	assert(window.size.x <= 396 and window.size.y <= 552)
	window.password.text = "clear-on-hide"
	window.hide()
	assert(window.password.text.is_empty())
	window.queue_free()
	service.queue_free()
	await process_frame
	print("PASS cloud account, selection, privacy, confirmation and bounded layout")
	quit()
