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

	func download(id: String, revision: String, path: String) -> Dictionary:
		calls.append(["download", id, revision, path])
		var bytes := Sc2xDocument.create_empty(16, "Cloud dialog test").document.serialize().data
		var file := FileAccess.open(path, FileAccess.WRITE)
		assert(file != null)
		file.store_buffer(bytes)
		file.close()
		return {"ok": true, "path": path}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.gui_embed_subwindows = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var service := FakeCloud.new()
	root.add_child(service)
	var shell := WindowScript.new()
	root.add_child(shell)
	var window := shell.content
	window.bind(service)
	assert(window.account_form.visible and not window.account_info.visible)
	assert(window.cloud_enabled.disabled)
	window.email.text = " test@example.invalid "
	window.password.text = "private-example"
	window.remember.button_pressed = true
	await window._authenticate()
	assert(service.calls[-1] == ["login", "test@example.invalid", "private-example", true])
	assert(window.password.text.is_empty())
	await _file_dialogs(service)
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
	shell.open()
	await process_frame
	assert(shell.size.x <= 396 and shell.size.y <= 552)
	var first_size := shell.size
	shell.open()
	assert(shell.size == first_size, "Reopening the standalone Cloud window cannot shrink it")
	window.password.text = "clear-on-hide"
	shell.hide()
	assert(window.password.text.is_empty())
	shell.queue_free()
	service.queue_free()
	await process_frame
	print("PASS cloud account, selection, privacy, confirmation and bounded layout")
	quit()


func _file_dialogs(service: FakeCloud) -> void:
	AppPaths._root = OS.get_temp_dir().path_join("cloud-dialog-test-" + Crypto.new().generate_random_bytes(8).hex_encode())
	service.data.saves = [{"id": "a", "head": "r1", "name": "City A", "deleted_at": null, "metadata": {"year": 1950, "population": 1200}}]
	service.data.account = {"email": "test@example.invalid"}
	root.size = Vector2i(420, 600)
	var picker := FileDialogFactory.city_open() as CityOpenDialog
	root.add_child(picker)
	picker.bind_cloud(service)
	picker.popup_centered(Vector2i(390, 520))
	await process_frame
	var local_path := picker.current_path
	picker.select_source(1)
	await process_frame
	assert(picker.cloud_panel.visible and not picker.get_ok_button().visible)
	assert(not picker._body.visible and picker.cloud_panel.saves.item_count == 1)
	assert(picker.cloud_panel.actions.download.get_parent() == picker.cloud_panel.browser_footer,
		"Load and version selection stay outside the scrollable library")
	assert(picker.cloud_panel.get_combined_minimum_size().x <= 396, "Embedded Cloud controls fit a narrow touchscreen")
	picker.cloud_panel.password.text = "clear-on-source-switch"
	picker.select_source(0)
	assert(picker.cloud_panel.password.text.is_empty())
	assert(picker.current_path == local_path and picker.get_ok_button().visible and picker._body.visible)
	picker.select_source(1)
	var loaded: Array = []
	picker.file_selected.connect(func(path: String) -> void: loaded.append(path))
	picker.cloud_panel.saves.select(0)
	await picker.cloud_panel._select_save(0)
	await picker.cloud_panel._choose_download()
	assert(loaded.size() == 1 and not picker.visible, "Cloud load returns a verified local path through the normal city loader")
	assert(Sc2File.load_path(loaded[0]).is_valid())
	assert(not picker.cloud_panel.file_dialog.visible, "Load requires no second save-file dialog")
	picker.queue_free()
	var save := FileDialogFactory.city_save() as CitySaveDialog
	root.add_child(save)
	save.bind_cloud(service)
	save.popup_centered(Vector2i(396, 520))
	# Headless popup placement clamps to its dummy 200x70 screen. Resize the
	# embedded window explicitly to exercise the real narrow-content layout.
	save.size = Vector2i(396, 520)
	for frame in 6:
		await process_frame
	assert(save.size.x <= 396 and save.size.y <= 552, "Wrapped Cloud help cannot inflate the save dialog")
	var layout_height := save.size.y / save.content_scale_factor
	assert(save.cloud_enabled.get_global_rect().end.y < layout_height,
		"Cloud controls must fit: %s / %s; body=%s; root=%s; max=%s; embedded=%s; native=%s" % [save.cloud_enabled.get_global_rect(), save.size, save.get_vbox().size, root.size, save.max_size, save.is_embedded(), save.force_native])
	assert(save.get_line_edit().get_global_rect().end.y < layout_height,
		"The filename and Cloud controls remain inside the actual save viewport")
	save.prepare_cloud("user://existing.sc2x")
	save.cloud_enabled.button_pressed = true
	assert(save.wants_cloud())
	assert(save.cloud_status.text.contains("test@example.invalid"))
	save.prepare_cloud("user://existing.sc2x", false)
	assert(not save.wants_cloud() and save.cloud_enabled.disabled, "Clients cannot enable host-only full multiplayer saves")
	save.prepare_cloud("user://existing.sc2x")
	service.data.account = {}
	service.changed.emit()
	assert(not save.cloud_status.text.is_empty())
	save.cloud_enabled.button_pressed = true
	assert(save.wants_cloud(), "Signed-out users can choose Cloud before the subsequent sign-in")
	save.queue_free()
	await process_frame
