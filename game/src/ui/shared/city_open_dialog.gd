class_name CityOpenDialog
extends FileDialog
## Preserve Godot's file navigation and add a read-only city preview beside it.

var assets: LoadedAssetState
var preview_panel: PanelContainer
var preview_image: TextureRect
var preview_name: Label
var preview_status: Label
var preview_details: Label
var displayed_details: Dictionary = {}
var selected_path := ""
var displayed_path := ""
var displayed_image: Image
var job: CityPreviewJob
var _job_path := ""
var _requested_msec := 0
var _body: BoxContainer
var sources: TabBar
var cloud_panel: CloudPanel
var _local_controls: Array[Control] = []
var save_list: CitySaveList
var favorites: CityFavorites
var _pending_upload := ""
var _upload_busy := false
var _fit_pending := true
var scenario_mode := false


func _ready() -> void:
	use_native_dialog = false
	wrap_controls = false
	mode_overrides_title = false
	title = "Open City"
	display_mode = FileDialog.DISPLAY_LIST
	set_customization_flag_enabled(FileDialog.CUSTOMIZATION_FAVORITES, false)
	set_customization_flag_enabled(FileDialog.CUSTOMIZATION_RECENT, false)
	favorites = CityFavorites.new()
	save_list = CitySaveList.new()
	save_list.configure(self)
	save_list.bind_favorites(favorites)
	save_list.upload_requested.connect(_upload_city)
	_translate_navigation.call_deferred()
	var navigation: HSplitContainer
	for child in get_vbox().get_children():
		if child is HSplitContainer:
			navigation = child
			break
	if navigation == null:
		_build_sources()
		return
	var index := navigation.get_index()
	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	get_vbox().add_child(_body)
	get_vbox().move_child(_body, index)
	navigation.reparent(_body)
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.size_flags_stretch_ratio = 7.0
	preview_panel = PanelContainer.new()
	preview_panel.name = "CityPreview"
	preview_panel.theme_type_variation = &"InformationPanel"
	preview_panel.custom_minimum_size.x = 240
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_stretch_ratio = 3.0
	_body.add_child(preview_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	var heading := Label.new()
	heading.text = "City preview"
	heading.theme_type_variation = &"SectionHeading"
	rows.add_child(heading)
	preview_image = TextureRect.new()
	preview_image.name = "Image"
	preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	preview_image.custom_minimum_size.y = 120
	preview_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(preview_image)
	preview_name = Label.new()
	preview_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preview_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview_name.theme_type_variation = &"SectionHeading"
	rows.add_child(preview_name)
	preview_details = Label.new()
	preview_details.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preview_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(preview_details)
	preview_status = Label.new()
	preview_status.text = "Select a city to preview."
	preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_status.theme_type_variation = &"HelpLabel"
	rows.add_child(preview_status)
	visibility_changed.connect(_visibility_changed)
	get_parent().get_viewport().size_changed.connect(_layout_preview)
	get_parent().get_viewport().size_changed.connect(_fit_bounds)
	size_changed.connect(func() -> void: _fit_pending = true)
	get_vbox().minimum_size_changed.connect(func() -> void: _fit_pending = true)
	_build_sources()
	_fit_bounds()


func _build_sources() -> void:
	for child in get_vbox().get_children():
		if child is Control:
			_local_controls.append(child)
	sources = TabBar.new()
	sources.add_tab("Local saves")
	sources.add_tab("Cloud saves")
	sources.custom_minimum_size.y = 44
	sources.tab_alignment = TabBar.ALIGNMENT_LEFT
	sources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sources.tab_changed.connect(select_source)
	get_vbox().add_child(sources)
	get_vbox().move_child(sources, 0)
	cloud_panel = CloudPanel.new()
	cloud_panel.configure_browser()
	cloud_panel.bind_favorites(favorites)
	get_vbox().add_child(cloud_panel)
	cloud_panel.close_requested.connect(hide)
	cloud_panel.downloaded.connect(func(path: String) -> void:
		hide()
		file_selected.emit(path))
	select_source(0)


func bind_cloud(service: Node) -> void:
	cloud_panel.bind(service)
	service.changed.connect(_resume_upload)
	if save_list != null:
		save_list.bind_cloud(service)


func select_source(index: int) -> void:
	if sources == null:
		return
	if scenario_mode:
		index = 0
	sources.set_current_tab(index)
	for control in _local_controls:
		control.visible = index == 0
	cloud_panel.visible = index == 1
	get_ok_button().visible = index == 0
	get_cancel_button().text = "Cancel" if index == 0 else "Close"
	if index == 1 and cloud_panel.sync != null:
		if job != null:
			job.cancel()
		cloud_panel.open()
	_fit_pending = true


func set_scenario_mode(enabled: bool) -> void:
	scenario_mode = enabled
	select_source(0)
	sources.visible = not enabled
	save_list.set_scenario_mode(enabled)


func _fit_bounds() -> void:
	var viewport := get_parent().get_viewport()
	var area := Vector2i(viewport.get_visible_rect().size)
	if viewport is Window:
		area = Vector2i(Vector2(viewport.size) / maxf(viewport.content_scale_factor, 0.001))
	max_size = Vector2i(maxi(1, area.x - 24), maxi(1, area.y - 48))
	if size.x > max_size.x or size.y > max_size.y:
		size = size.min(max_size)
	_fit_pending = true


func _fit_content() -> void:
	# Bound the body independently of dynamic previews and Cloud page minima.
	# Let the page's ScrollContainer handle overflow instead of growing the window.
	var panel := get_theme_stylebox("panel", "AcceptDialog")
	var footer := get_ok_button().get_parent_control()
	var margin := Vector2(panel.get_content_margin(SIDE_LEFT), panel.get_content_margin(SIDE_TOP))
	var end_margin := Vector2(panel.get_content_margin(SIDE_RIGHT), panel.get_content_margin(SIDE_BOTTOM)
		+ footer.get_combined_minimum_size().y + get_theme_constant("buttons_separation", "AcceptDialog"))
	get_vbox().position = margin
	get_vbox().size = (Vector2(size) / maxf(content_scale_factor, 0.001) - margin - end_margin).max(Vector2.ONE)


func _layout_preview() -> void:
	if preview_panel != null:
		# The containing viewport is independent of this dialog's minimum size.
		# Basing the minimum on the resulting dialog width feeds size changes
		# back into FileDialog's wrapping and the saved-window bounds clamp.
		_body.vertical = get_parent().get_viewport().get_visible_rect().size.x * 0.8 < 760
		preview_panel.custom_minimum_size = Vector2(0 if _body.vertical else 240,
			160 if _body.vertical else 0)
		preview_panel.size_flags_vertical = Control.SIZE_FILL if _body.vertical else Control.SIZE_EXPAND_FILL
		preview_panel.size_flags_stretch_ratio = 1.0 if _body.vertical else 3.0
		preview_image.custom_minimum_size.y = 80 if _body.vertical else 120


func _visibility_changed() -> void:
	selected_path = ""
	if not visible and job != null:
		job.cancel()
	if not visible and cloud_panel != null:
		cloud_panel.clear_secrets()
	if visible:
		favorites.reload()
		display_mode = FileDialog.DISPLAY_LIST
		_translate_navigation.call_deferred()
		_layout_preview()
		_fit_bounds()
	else:
		_pending_upload = ""


func _process(_delta: float) -> void:
	if visible and _fit_pending:
		_fit_pending = false
		_fit_content()
	if preview_panel == null:
		return
	if visible and job != null and _job_path == selected_path and not job.cancelled():
		var details := job.details()
		if details != displayed_details:
			displayed_details = details
			_update_details()
	if job != null and job.finished():
		job.join()
		if visible and _job_path == selected_path and not job.cancelled():
			displayed_details = job.details()
			_update_details()
			displayed_path = _job_path
			displayed_image = job.image
			preview_image.texture = ImageTexture.create_from_image(job.image) if job.image != null else null
			preview_status.text = ("Saved city preview" if job.saved_preview else "City overview") if job.image != null else "Preview unavailable. You can still open this city."
		job = null
	if not visible:
		return
	if cloud_panel != null and cloud_panel.visible:
		return
	var path := current_path
	if path != selected_path:
		selected_path = path
		_requested_msec = Time.get_ticks_msec()
		displayed_image = null
		displayed_path = ""
		preview_image.texture = null
		displayed_details = {}
		preview_details.text = ""
		preview_name.text = path.get_file().get_basename() if _is_city(path) else ""
		preview_status.text = "Preparing city preview…" if _is_city(path) else "Select a city to preview."
		if job != null:
			job.cancel()
	if job == null and selected_path != displayed_path and Time.get_ticks_msec() - _requested_msec >= 250 and _is_city(selected_path):
		job = CityPreviewJob.for_assets(assets) if assets != null else CityPreviewJob.new()
		job.path = selected_path
		_job_path = selected_path
		job.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and preview_details != null:
		_update_details()
		_translate_navigation.call_deferred()


func _translate_navigation() -> void:
	# Engine-owned labels do not all use the game's central TranslationServer.
	for label in get_vbox().find_children("*", "Label", true, false):
		if label.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED and label.text in ["Directories & Files:", "Path:", "File:", "Filter:"]:
			label.set_meta("city_library_source", label.text)
		if label.has_meta("city_library_source"):
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			label.text = tr(str(label.get_meta("city_library_source")))


func _upload_city(path: String) -> void:
	if _upload_busy or cloud_panel.sync == null:
		return
	if cloud_panel.sync.snapshot().get("account", {}).is_empty():
		_pending_upload = path
		select_source(1)
		return
	_upload_busy = true
	var result: Dictionary = await cloud_panel.sync.upload_local_file(path)
	_upload_busy = false
	if not is_instance_valid(self) or not visible:
		return
	cloud_panel.notice.text = tr("Waiting to upload") if result.ok else tr(CloudPanel.error_message(str(result.get("error", ""))))
	cloud_panel.notice.show()
	select_source(1)


func _resume_upload() -> void:
	if not visible or _pending_upload.is_empty() or cloud_panel.sync == null or cloud_panel.sync.snapshot().get("account", {}).is_empty():
		return
	var path := _pending_upload
	_pending_upload = ""
	_upload_city.call_deferred(path)


func _update_details() -> void:
	var info := displayed_details
	if info.is_empty():
		preview_details.text = ""
		return
	if not str(info.get("city_name", "")).is_empty():
		preview_name.text = info.city_name
	var lines := PackedStringArray()
	if info.multiplayer:
		var mode := ""
		match info.get("mode", "unknown"):
			"coop":
				mode = tr("Co-op")
			"shared":
				mode = tr("Competitive Shared")
			"region":
				mode = tr("Competitive Region")
		lines.append(tr("Multiplayer") + (" · " + mode if not mode.is_empty() else ""))
	else:
		lines.append(tr("Single-player city"))
	lines.append(tr("Terrain: %d × %d tiles") % [info.map_size, info.map_size])
	if info.has("year"):
		lines.append(tr("Year: %d") % info.year)
	if info.has("population"):
		lines.append(tr("Population: %s") % DisplayNumberFormat.format(info.population))
	if info.has("funds"):
		lines.append(tr("City funds: %s") % ("$" + DisplayNumberFormat.format(info.funds)))
	if info.has("bank_debt"):
		lines.append(tr("Bank debt: %s") % ("$" + DisplayNumberFormat.format(info.bank_debt)))
	if info.has("players"):
		lines.append(tr("Saved players: %d") % info.players)
	if info.get("separate_finances", false):
		lines.append(tr("Player finances are not shown in this preview."))
	preview_details.text = "\n".join(lines)


func image_for_path(path: String) -> Image:
	return displayed_image if displayed_path == path else null


static func _is_city(path: String) -> bool:
	return path.get_extension().to_lower() in ["sc2", "sc2x", "scn", "cty"] and FileAccess.file_exists(path)


func _exit_tree() -> void:
	if job != null:
		job.cancel()
		job.join()
