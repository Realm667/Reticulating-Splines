class_name CitySaveDialog
extends FileDialog
## Keep local saving primary and make the optional Cloud destination explicit.

signal cloud_save_requested(path: String)

var sync: Node
var cloud_enabled: CheckBox
var cloud_status: Label
var manage: Button
var account_window: CloudWindow
var saved_path := ""
var host_allowed := true
var _help: AcceptDialog
var _signed_in_icon: Texture2D
var _signed_out_icon: Texture2D


func _ready() -> void:
	use_native_dialog = false
	# Wrapped help initially has no width. Do not feed its transient height
	# back into the window size before FileDialog has laid out its contents.
	wrap_controls = false
	mode_overrides_title = false
	title = "Save City"
	display_mode = FileDialog.DISPLAY_LIST
	var group := HBoxContainer.new()
	var native_footer := get_ok_button().get_parent_control()
	var footer := HBoxContainer.new()
	get_vbox().add_child(footer)
	get_ok_button().reparent(footer)
	get_cancel_button().reparent(footer)
	native_footer.hide()
	footer.add_child(group)
	footer.move_child(group, 0)
	cloud_enabled = CheckBox.new()
	cloud_enabled.text = "Cloud synchronization"
	cloud_enabled.tooltip_text = "Cloud synchronization"
	cloud_enabled.custom_minimum_size.y = 40
	footer.add_child(cloud_enabled)
	footer.move_child(cloud_enabled, get_ok_button().get_index() + 1)
	cloud_status = Label.new()
	cloud_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	group.add_child(cloud_status)
	cloud_status.hide()
	manage = Button.new()
	manage.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	manage.clip_text = true
	manage.custom_minimum_size.y = 40
	group.add_child(manage)
	manage.pressed.connect(_manage_cloud)
	var help := Button.new()
	help.text = "?"
	help.tooltip_text = "Cloud synchronization"
	help.pressed.connect(_show_help)
	group.add_child(help)
	_signed_in_icon = _status_icon(Color("72c581"))
	_signed_out_icon = _status_icon(Color("ee7676"))
	# Keep Godot's action buttons and keyboard handling in one full-width row.
	var middle := Control.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(middle)
	footer.move_child(middle, 1)
	footer.move_child(get_ok_button(), 2)
	footer.move_child(cloud_enabled, 3)
	var end_gap := Control.new()
	end_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_gap.custom_minimum_size.x = 16
	footer.add_child(end_gap)
	footer.move_child(end_gap, 4)
	footer.move_child(get_cancel_button(), 5)
	footer.add_theme_constant_override("separation", 8)
	visibility_changed.connect(func() -> void:
		if visible:
			display_mode = FileDialog.DISPLAY_LIST
		elif account_window != null:
			account_window.hide())
	get_parent().get_viewport().size_changed.connect(_fit_bounds)
	size_changed.connect(func() -> void: _fit_content.call_deferred())
	visibility_changed.connect(func() -> void: _fit_content.call_deferred())
	get_vbox().minimum_size_changed.connect(func() -> void: _fit_content.call_deferred())
	_fit_bounds()
	_refresh_cloud()


func _fit_bounds() -> void:
	var viewport := get_parent().get_viewport()
	var area := Vector2i(viewport.get_visible_rect().size)
	if viewport is Window:
		area = Vector2i(Vector2(viewport.size) / maxf(viewport.content_scale_factor, 0.001))
	max_size = Vector2i(maxi(1, area.x - 24), maxi(1, area.y - 48))
	if size.x > max_size.x or size.y > max_size.y:
		size = Vector2i(mini(size.x, max_size.x), mini(size.y, max_size.y))
	set_customization_flag_enabled(FileDialog.CUSTOMIZATION_FAVORITES, false)
	set_customization_flag_enabled(FileDialog.CUSTOMIZATION_RECENT, false)
	_fit_content.call_deferred()


func _fit_content() -> void:
	var body := get_vbox()
	var panel := get_theme_stylebox("panel", "AcceptDialog")
	var margin := Vector2(panel.get_content_margin(SIDE_LEFT), panel.get_content_margin(SIDE_TOP))
	var end_margin := Vector2(panel.get_content_margin(SIDE_RIGHT), panel.get_content_margin(SIDE_BOTTOM))
	body.position = margin
	# The embedded render viewport can still have its initial size before its
	# first draw (and throughout a headless test). Use the window's layout size.
	var layout_size := Vector2(size) / maxf(content_scale_factor, 0.001)
	cloud_enabled.text = "Cloud" if layout_size.x < 600 else "Cloud synchronization"
	manage.custom_minimum_size.x = clampf(layout_size.x * 0.24, 90, 280)
	body.size = (layout_size - margin - end_margin).max(Vector2.ONE)


func bind_cloud(service: Node) -> void:
	if sync != null and sync.changed.is_connected(_refresh_cloud):
		sync.changed.disconnect(_refresh_cloud)
	sync = service
	sync.changed.connect(_refresh_cloud)
	_refresh_cloud()


func prepare_cloud(path: String, may_save := true) -> void:
	saved_path = path
	host_allowed = may_save
	cloud_enabled.set_pressed_no_signal(sync != null and sync.is_enabled(path))
	cloud_enabled.tooltip_text = "Enable Cloud for this copy. A new filename creates a separate Cloud city. Leave unchecked for a local copy."
	_refresh_cloud()


func wants_cloud() -> bool:
	return host_allowed and cloud_enabled.button_pressed


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and cloud_status != null:
		_refresh_cloud()


func _refresh_cloud() -> void:
	if cloud_enabled == null:
		return
	cloud_enabled.disabled = not host_allowed
	if not host_allowed:
		cloud_status.text = tr("Only the host can save a multiplayer game.")
		return
	var state: Dictionary = sync.snapshot() if sync != null else {}
	var account: Dictionary = state.get("account", {})
	manage.text = tr("Sign in") if account.is_empty() else str(account.get("email", ""))
	manage.icon = _signed_out_icon if account.is_empty() else _signed_in_icon
	cloud_status.text = tr("Not signed in") if account.is_empty() else tr("Signed in as %s") % str(account.get("email", ""))
	if not str(state.get("error", "")).is_empty():
		cloud_status.text += " · " + tr(CloudPanel.error_message(str(state.error)))
	elif bool(state.get("busy", false)):
		cloud_status.text += " · " + tr("Working…")
	manage.tooltip_text = cloud_status.text


static func _status_icon(color: Color) -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><circle cx="7" cy="7" r="5" fill="#%s"/></svg>' % color.to_html(false))
	return ImageTexture.create_from_image(image)


func _show_help() -> void:
	if _help == null:
		_help = AcceptDialog.new()
		_help.title = "Cloud synchronization"
		_help.dialog_text = "The local copy is saved first. Cloud uploads continue in the background, including after an offline session."
		_help.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_help.get_label().custom_minimum_size.x = 240
		add_child(_help)
	_help.popup_centered(Vector2i(480, 180).min(max_size))


func _manage_cloud() -> void:
	if sync == null:
		return
	if account_window == null:
		account_window = CloudWindow.new()
		add_child(account_window)
		account_window.bind(sync)
		account_window.opt_in_changed.connect(func(path: String, enabled: bool) -> void:
			if path == saved_path:
				cloud_enabled.set_pressed_no_signal(enabled)
			if enabled:
				cloud_save_requested.emit(path))
	account_window.set_current_path(saved_path if host_allowed else "")
	account_window.open()
