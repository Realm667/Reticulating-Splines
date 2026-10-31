class_name CloudWindow
extends QolDialog
## Private saves UI; passwords only live in transient fields.

signal downloaded(path: String)
signal opt_in_changed(path: String, enabled: bool)

var sync: Node
var state: Dictionary = {}
var tabs: TabContainer
var status: Label
var quota: Label
var notice: Label
var account_form: VBoxContainer
var account_info: VBoxContainer
var email: LineEdit
var password: LineEdit
var code: LineEdit
var auth_mode: OptionButton
var remember: CheckBox
var remembered_access: CheckBox
var auth_busy := false
var submit: Button
var saves: ItemList
var save_rows: Array = []
var versions: OptionButton
var version_rows: Array = []
var details: Label
var preview: TextureRect
var deleted: CheckBox
var cloud_enabled: CheckBox
var current_path := ""
var selected_save := ""
var selected_head := ""
var devices: ItemList
var device_rows: Array = []
var conflicts: VBoxContainer
var actions: Dictionary = {}
var confirm: ConfirmationDialog
var file_dialog: FileDialog
var pending_action: Callable
var pending_download: Dictionary = {}
var request_generation := 0


func _init() -> void:
	super()
	title = "Account & Cloud"
	wrap_controls = false
	min_size = Vector2i(300, 260)
	size = Vector2i(760, 620)
	status = _text(column, "")
	quota = _text(column, "")
	notice = _text(column, "")
	notice.hide()
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	_build_account(_page("Account"))
	_build_saves(_page("Cloud saves"))
	_build_devices(_page("Devices"))
	_action(column, "Close", hide)
	confirm = ConfirmationDialog.new()
	confirm.dialog_autowrap = true
	confirm.exclusive = true
	confirm.confirmed.connect(func() -> void:
		var action := pending_action
		pending_action = Callable()
		if action.is_valid():
			action.call())
	add_child(confirm)
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.sc2x ; SC2X", "*.sc2 ; SC2"])
	file_dialog.file_selected.connect(_download)
	add_child(file_dialog)
	visibility_changed.connect(func() -> void:
		if not visible:
			password.clear()
			code.clear())


func _ready() -> void:
	get_parent().get_viewport().size_changed.connect(_refit_visible)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and sync != null and saves != null:
		refresh()
		var selected := saves.get_selected_items()
		if not selected.is_empty():
			_show_save_metadata(save_rows[selected[0]])


func _refit_visible() -> void:
	if visible:
		_fit(self, Vector2i(760, 620))
	if confirm.visible:
		_fit(confirm, Vector2i(520, 230))
	if file_dialog.visible:
		_fit(file_dialog, Vector2i(760, 520))


func bind(service: Node) -> void:
	if sync != null and sync.changed.is_connected(refresh):
		sync.changed.disconnect(refresh)
	sync = service
	sync.changed.connect(refresh)
	refresh()


func open() -> void:
	theme = AppUiTheme.current()
	refresh()
	_fit(self, Vector2i(760, 620))
	if sync != null and not (state.get("account", {}) as Dictionary).is_empty():
		sync.refresh()


func set_current_path(path: String) -> void:
	if current_path == path:
		return
	current_path = path
	refresh()


func confirm_exit(callback: Callable) -> void:
	if sync != null:
		state = sync.snapshot()
	for job: Dictionary in state.get("queue", []):
		if str(job.get("status", "")) in ["queued", "retry", "uploading", "conflict"]:
			_ask("Uploads are pending. Quit now? They remain queued and resume when you sign in again.", callback)
			return
	callback.call()


func _page(caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	return content


func _text(parent: Control, value: String) -> Label:
	var result := Label.new()
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result


func _field(parent: Control, caption: String, secret := false) -> LineEdit:
	_text(parent, caption)
	var result := LineEdit.new()
	result.secret = secret
	result.custom_minimum_size.y = 40
	result.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secret else LineEdit.KEYBOARD_TYPE_DEFAULT
	parent.add_child(result)
	return result


func _flow(parent: Control) -> HFlowContainer:
	var result := HFlowContainer.new()
	parent.add_child(result)
	return result


func _action(parent: Control, caption: String, callback: Callable) -> Button:
	var result := button(parent, caption, callback)
	result.custom_minimum_size.y = 40
	return result


func _build_account(content: VBoxContainer) -> void:
	_text(content, "Private saves across your devices. Each save stays local unless you enable Cloud.")
	account_form = VBoxContainer.new()
	content.add_child(account_form)
	auth_mode = OptionButton.new()
	for caption in ["Sign in", "Register", "Verify email", "Reset password"]:
		auth_mode.add_item(caption)
	auth_mode.custom_minimum_size.y = 40
	account_form.add_child(auth_mode)
	email = _field(account_form, "Email")
	email.max_length = 254
	email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	password = _field(account_form, "Password", true)
	password.max_length = 1024
	password.tooltip_text = "Use at least 12 characters for a new password."
	code = _field(account_form, "Email code")
	code.max_length = 8
	_text(account_form, "Enter the code from your email here. After verification or a password reset, sign in with your password.")
	remember = CheckBox.new()
	remember.text = "Stay signed in on this device"
	remember.custom_minimum_size.y = 40
	account_form.add_child(remember)
	_text(account_form, "Your password is never saved. Remembered access uses your operating system's protected credential storage.")
	var auth_actions := _flow(account_form)
	submit = _action(auth_actions, "Continue", _authenticate)
	_action(auth_actions, "Send reset code", _request_reset)
	auth_mode.item_selected.connect(func(_index: int) -> void: _show_auth_fields())
	account_info = VBoxContainer.new()
	content.add_child(account_info)
	remembered_access = CheckBox.new()
	remembered_access.text = "Stay signed in on this device"
	remembered_access.custom_minimum_size.y = 40
	account_info.add_child(remembered_access)
	remembered_access.toggled.connect(func(enabled: bool) -> void:
		await sync.set_remember(enabled)
		refresh())
	_action(account_info, "Sign out", func() -> void: sync.logout())
	_show_auth_fields()


func _show_auth_fields() -> void:
	password.visible = auth_mode.selected != 2
	password.get_parent().get_child(password.get_index() - 1).visible = password.visible
	code.visible = auth_mode.selected in [2, 3]
	code.get_parent().get_child(code.get_index() - 1).visible = code.visible
	remember.visible = auth_mode.selected == 0
	password.clear()
	code.clear()


func _authenticate() -> void:
	if sync == null or auth_busy or bool(state.get("busy", false)):
		return
	auth_busy = true
	submit.disabled = true
	var secret := password.text
	var challenge := code.text.strip_edges()
	password.clear()
	code.clear()
	match auth_mode.selected:
		0:
			await sync.login(email.text.strip_edges(), secret, remember.button_pressed)
		1:
			var result: Dictionary = await sync.register(email.text.strip_edges(), secret)
			if bool(result.get("ok", false)):
				auth_mode.select(2)
				_show_auth_fields()
		2:
			var result: Dictionary = await sync.verify(email.text.strip_edges(), challenge)
			if bool(result.get("ok", false)):
				auth_mode.select(0)
				_show_auth_fields()
		3:
			var result: Dictionary = await sync.reset_password(email.text.strip_edges(), challenge, secret)
			if bool(result.get("ok", false)):
				auth_mode.select(0)
				_show_auth_fields()
	secret = ""
	auth_busy = false
	refresh()


func _request_reset() -> void:
	if sync == null or auth_busy or bool(state.get("busy", false)):
		return
	auth_busy = true
	await sync.request_reset(email.text.strip_edges())
	auth_busy = false
	auth_mode.select(3)
	_show_auth_fields()
	refresh()


func _build_saves(content: VBoxContainer) -> void:
	cloud_enabled = CheckBox.new()
	cloud_enabled.text = "Keep this save in Cloud"
	cloud_enabled.custom_minimum_size.y = 40
	content.add_child(cloud_enabled)
	cloud_enabled.toggled.connect(func(enabled: bool) -> void:
		if sync != null and not current_path.is_empty():
			var result: Dictionary = sync.set_enabled(current_path, enabled)
			if bool(result.get("ok", false)):
				opt_in_changed.emit(current_path, enabled)
			refresh())
	_text(content, "Local deletion does not delete Cloud copies. Regions are stored together. Only the host can save a multiplayer game.")
	_text(content, "Cloud keeps five versions per save. Trash is removed after 30 days. Versions and trash count toward your quota.")
	var filters := _flow(content)
	_action(filters, "Refresh", _refresh_cloud)
	deleted = CheckBox.new()
	deleted.text = "Trash"
	deleted.custom_minimum_size.y = 40
	filters.add_child(deleted)
	deleted.toggled.connect(func(_value: bool) -> void: refresh())
	saves = ItemList.new()
	saves.custom_minimum_size.y = 140
	saves.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(saves)
	saves.item_selected.connect(_select_save)
	details = _text(content, "Select a save.")
	preview = TextureRect.new()
	preview.custom_minimum_size.y = 140
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.hide()
	content.add_child(preview)
	versions = OptionButton.new()
	versions.custom_minimum_size.y = 40
	versions.item_selected.connect(func(_index: int) -> void: _show_version_preview())
	content.add_child(versions)
	var buttons := _flow(content)
	actions.download = _action(buttons, "Download", _choose_download)
	actions.restore = _action(buttons, "Restore version", _confirm_restore)
	actions.trash = _action(buttons, "Move to trash", _confirm_trash)
	actions.undelete = _action(buttons, "Restore from trash", _undelete)
	conflicts = VBoxContainer.new()
	content.add_child(conflicts)


func _build_devices(content: VBoxContainer) -> void:
	_text(content, "Revoking a device signs it out. Its local saves remain on that device.")
	devices = ItemList.new()
	devices.custom_minimum_size.y = 160
	devices.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(devices)
	_action(content, "Revoke device", _confirm_revoke)


func refresh() -> void:
	if sync == null:
		return
	state = sync.snapshot()
	var signed_in := not (state.get("account", {}) as Dictionary).is_empty()
	account_form.visible = not signed_in
	account_info.visible = signed_in
	remembered_access.set_pressed_no_signal(bool(state.get("remember", false)))
	var error := str(state.get("error", ""))
	status.text = tr(error_message(error)) if not error.is_empty() else tr("Signed in as %s") % str(state.account.get("email", "")) if signed_in else tr("Not signed in")
	if bool(state.get("busy", false)) or auth_busy:
		status.text += " · " + tr("Working…")
	var usage: Dictionary = state.get("usage", {})
	var pending := 0
	for job: Dictionary in state.get("queue", []):
		if str(job.get("status", "")) in ["queued", "retry", "uploading", "conflict"]:
			pending += 1
	quota.text = tr("Cloud storage: %s / %s · Pending uploads: %d") % [String.humanize_size(int(usage.get("used_bytes", 0))), String.humanize_size(int(usage.get("quota_bytes", 0))), pending]
	quota.visible = signed_in
	submit.disabled = bool(state.get("busy", false)) or auth_busy
	cloud_enabled.disabled = current_path.is_empty() or not signed_in
	cloud_enabled.set_pressed_no_signal(not current_path.is_empty() and sync.is_enabled(current_path))
	cloud_enabled.tooltip_text = current_path if not current_path.is_empty() else tr("Save locally first, then enable Cloud.")
	save_rows.clear()
	saves.clear()
	for item: Dictionary in state.get("saves", []):
		var deleted_at: Variant = item.get("deleted_at")
		var in_trash := deleted_at != null and not str(deleted_at).is_empty()
		if in_trash != deleted.button_pressed:
			continue
		save_rows.append(item)
		saves.add_item(str(item.get("name", "")) + " · " + tr(_save_status(item)))
		if str(item.get("id", "")) == selected_save:
			saves.select(saves.item_count - 1)
	if saves.get_selected_items().is_empty():
		selected_save = ""
		selected_head = ""
		versions.clear()
		version_rows.clear()
		details.text = tr("Select a save.")
		preview.hide()
	for action: Button in actions.values():
		action.disabled = selected_save.is_empty() or bool(state.get("busy", false)) or not signed_in
	actions.download.disabled = actions.download.disabled or version_rows.is_empty()
	actions.restore.disabled = actions.restore.disabled or version_rows.is_empty()
	actions.trash.visible = not deleted.button_pressed
	actions.restore.visible = not deleted.button_pressed
	actions.undelete.visible = deleted.button_pressed
	var device_selection := devices.get_selected_items()
	var device_id := str(device_rows[device_selection[0]].get("id", "")) if not device_selection.is_empty() and device_selection[0] < device_rows.size() else ""
	device_rows = state.get("devices", [])
	devices.clear()
	for device: Dictionary in device_rows:
		devices.add_item("%s · %s%s" % [str(device.get("name", "")), str(device.get("last_seen", "")), " · " + tr("This device") if bool(device.get("current", false)) else ""])
		if str(device.get("id", "")) == device_id:
			devices.select(devices.item_count - 1)
	_show_conflicts()


func _save_status(item: Dictionary) -> String:
	if item.get("deleted_at") != null and not str(item.get("deleted_at", "")).is_empty():
		return "Trash"
	for job: Dictionary in state.get("queue", []):
		if job.get("save_id") != item.get("id"):
			continue
		if job.get("status") == "conflict":
			return "Conflicting versions"
		if job.get("status") in ["queued", "retry", "uploading"]:
			return "Waiting to upload"
	return "Cloud copy available"


func _refresh_cloud() -> void:
	if sync != null:
		await sync.refresh()
		sync.pump()


func _select_save(index: int) -> void:
	if index < 0 or index >= save_rows.size():
		return
	var item: Dictionary = save_rows[index]
	selected_save = str(item.get("id", ""))
	selected_head = str(item.get("head", ""))
	versions.clear()
	version_rows.clear()
	_show_save_metadata(item)
	request_generation += 1
	var generation := request_generation
	for action: Button in actions.values():
		action.disabled = true
	var result: Dictionary = await sync.list_versions(selected_save)
	if generation != request_generation or selected_save != str(item.get("id", "")):
		return
	if bool(result.get("ok", false)):
		version_rows = result.get("versions", [])
		for version: Dictionary in version_rows:
			versions.add_item("%s · %s" % [str(version.get("created_at", "")), str(version.get("device_name", ""))])
		if not version_rows.is_empty():
			_show_version_preview()
	for action: Button in actions.values():
		action.disabled = bool(state.get("busy", false))
	actions.download.disabled = version_rows.is_empty()
	actions.restore.disabled = version_rows.is_empty()


func _show_save_metadata(item: Dictionary) -> void:
	var metadata: Dictionary = item.get("metadata", {})
	details.text = "%s\n" % str(item.get("name", "")) + tr("Year: %s · Population: %s\nUpdated: %s · Device: %s") % [str(metadata.get("year", "—")), str(metadata.get("population", "—")), str(item.get("updated_at", "—")), str(item.get("device_name", "—"))]
	_set_preview(str(metadata.get("preview", "")))
	if not version_rows.is_empty():
		_show_version_preview()


func _show_version_preview() -> void:
	if versions.selected < 0 or versions.selected >= version_rows.size():
		return
	var metadata: Variant = version_rows[versions.selected].get("metadata", {})
	_set_preview(str(metadata.get("preview", "")) if metadata is Dictionary else "")


func _set_preview(encoded: String) -> void:
	preview.texture = null
	preview.hide()
	if encoded.is_empty() or encoded.length() > 131_072 or encoded.length() % 4 != 0:
		return
	var alphabet := RegEx.new()
	alphabet.compile("^[A-Za-z0-9+/]*={0,2}$")
	if alphabet.search(encoded) == null:
		return
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return
	var width := (int(bytes[16]) << 24) | (int(bytes[17]) << 16) | (int(bytes[18]) << 8) | bytes[19]
	var height := (int(bytes[20]) << 24) | (int(bytes[21]) << 16) | (int(bytes[22]) << 8) | bytes[23]
	if width <= 0 or height <= 0 or width > 384 or height > 256:
		return
	var image := Image.new()
	if image.load_png_from_buffer(bytes) == OK:
		preview.texture = ImageTexture.create_from_image(image)
		preview.show()


func _revision() -> String:
	return str(version_rows[versions.selected].get("revision", "")) if versions.selected >= 0 and versions.selected < version_rows.size() else ""


func _choose_download() -> void:
	if selected_save.is_empty() or _revision().is_empty():
		return
	pending_download = {"id": selected_save, "revision": _revision()}
	file_dialog.current_file = "cloud-city.sc2x"
	_fit(file_dialog, Vector2i(760, 520))


func _download(path: String) -> void:
	var request := pending_download.duplicate()
	pending_download.clear()
	if request.is_empty():
		return
	var result: Dictionary = await sync.download(request.id, request.revision, path)
	if bool(result.get("ok", false)):
		downloaded.emit(str(result.get("path", path)))
	refresh()


func _ask(caption: String, callback: Callable) -> void:
	pending_action = callback
	confirm.title = tr("Account & Cloud")
	confirm.dialog_text = tr(caption)
	_fit(confirm, Vector2i(520, 230))


func _confirm_restore() -> void:
	if not selected_save.is_empty() and not _revision().is_empty():
		_ask("Restore this version as the current Cloud save? Your local file stays unchanged.", _restore.bind(selected_save, _revision(), selected_head))


func _restore(id: String, revision: String, head: String) -> void:
	await sync.restore_version(id, revision, head)
	await sync.refresh()


func _confirm_trash() -> void:
	if not selected_save.is_empty():
		_ask("Move this Cloud save to trash? Local files stay unchanged.", _trash.bind(selected_save))


func _trash(id: String) -> void:
	await sync.trash(id)
	await sync.refresh()


func _undelete() -> void:
	if not selected_save.is_empty():
		await sync.undelete(selected_save)
		await sync.refresh()


func _confirm_revoke() -> void:
	var selected := devices.get_selected_items()
	if not selected.is_empty():
		_ask("Revoke this device's account access?", _revoke.bind(str(device_rows[selected[0]].get("id", ""))))


func _revoke(id: String) -> void:
	await sync.revoke_device(id)
	await sync.refresh()


func _show_conflicts() -> void:
	for child in conflicts.get_children():
		conflicts.remove_child(child)
		child.queue_free()
	for conflict: Dictionary in state.get("conflicts", []):
		_text(conflicts, tr("Conflicting versions: %s") % str(conflict.get("name", "")))
		_text(conflicts, "Both versions are preserved until you choose. Cities and regions are never merged automatically.")
		var choices := _flow(conflicts)
		for choice in [["cloud", "Use Cloud version"], ["local", "Use local version"], ["both", "Keep both copies"]]:
			_action(choices, choice[1], _confirm_conflict.bind(str(conflict.get("id", "")), str(choice[0])))


func _confirm_conflict(id: String, choice: String) -> void:
	_ask("Apply this conflict resolution? Keep both copies if you want to continue both versions separately.", _resolve.bind(id, choice))


func _resolve(id: String, choice: String) -> void:
	var result: Dictionary = await sync.resolve_conflict(id, choice)
	if bool(result.get("ok", false)) and choice == "cloud":
		notice.text = tr("Cloud version selected. Download it to a new local file to continue. Your previous local file is preserved.")
		notice.show()
	refresh()


func _fit(dialog: Window, preferred: Vector2i) -> void:
	var area := Vector2i(get_parent().get_viewport().get_visible_rect().size)
	dialog.min_size = Vector2i(mini(300, maxi(1, area.x - 24)), mini(220, maxi(1, area.y - 48)))
	dialog.max_size = Vector2i(maxi(1, area.x - 24), maxi(1, area.y - 48))
	dialog.popup_centered(Vector2i(mini(preferred.x, dialog.max_size.x), mini(preferred.y, dialog.max_size.y)))


static func error_message(error: String) -> String:
	match error:
		"offline": return "Cloud is unavailable. Your local saves remain available."
		"unauthorized": return "Sign in again to access Cloud saves."
		"conflict", "revision_conflict": return "Choose how to resolve the conflicting save versions."
		"invalid_save": return "This save could not be verified. Your existing files are unchanged."
		"checksum_mismatch": return "This save could not be verified. Your existing files are unchanged."
		"incompatible_save": return "This save requires a different game or gameplay mod version."
		"storage_error": return "Cloud storage could not be updated. Try again."
		"quota_exceeded": return "Your Cloud storage is full."
		"invalid_credentials": return "Email or password is incorrect."
		"invalid_code", "expired_code": return "The email code is invalid or expired."
		"rate_limited": return "Too many attempts. Please try again later."
		"unverified", "verification_required": return "Verify your email before signing in."
		"invalid_email": return "Enter a valid email address."
		"invalid_password": return "Use at least 12 characters for a new password."
		"mail_unavailable": return "The email could not be sent. Please try again later."
		"version_expired", "not_found": return "This Cloud version is no longer available. Refresh the list."
		"credential_unavailable": return "Secure credential storage is unavailable"
		"host_only": return "Only the host can save a multiplayer game."
		"target_exists": return "Choose a new file name. Existing files are not overwritten."
		_: return "The Cloud request failed. Please try again."
