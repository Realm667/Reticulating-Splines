class_name CitySaveList
extends CityLibraryTable
## A detailed view of the native file list, retaining its navigation and selection.

signal upload_requested(path: String)
const STAR := preload("res://src/ui/shared/city_star.svg")
const FILLED_STAR := preload("res://src/ui/shared/city_star_filled.svg")
const TITLES := ["Favorite", "File name", "Date modified", "Game mode", "Multi-region", "Expanded", "Cloud"]
var dialog: FileDialog
var native_list: ItemList
var cloud: Node
var favorites: CityFavorites
var context: PopupMenu
var _context_path := ""
var _context_signature: Array = []
var _signature: Array = []
var _job_signature: Array = []
var _task := -1
var _results: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _elapsed := 0.0
var _metadata_age := 0.0
var _cancelled := false
var _mutex := Mutex.new()
var _sort_column := 1
var _descending := false
var scenario_mode := false


func configure(owner_dialog: FileDialog) -> void:
	dialog = owner_dialog
	for control in dialog.get_vbox().find_children("*", "ItemList", true, false):
		# The file list follows Godot's favourites and recent-folder ItemLists.
		if control.get_parent() is VBoxContainer and control.size_flags_vertical & Control.SIZE_EXPAND:
			native_list = control
	if native_list == null:
		queue_free()
		return
	columns = TITLES.size()
	column_titles_visible = true
	hide_root = true
	select_mode = Tree.SELECT_ROW
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	native_list.get_parent().add_child(self)
	native_list.get_parent().move_child(self, native_list.get_index())
	set_column_expand(0, false)
	set_column_expand_ratio(1, 3)
	for column in columns:
		set_column_custom_minimum_width(column, [40, 150, 135, 105, 105, 85, 65][column])
		set_column_clip_content(column, true)
	for column in range(2, columns):
		set_column_expand_ratio(column, 1)
	item_selected.connect(_selected)
	item_activated.connect(_activated)
	column_title_clicked.connect(_sort)
	theme_changed.connect(func() -> void:
		dialog.invalidate()
		_signature.clear()
		_draw_rows.call_deferred())
	button_clicked.connect(_star_clicked)
	gui_input.connect(_context_input)
	native_list.gui_input.connect(_native_context_input)
	context = PopupMenu.new()
	dialog.add_child(context)
	context.id_pressed.connect(_context_action)
	dialog.visibility_changed.connect(func() -> void: _signature.clear())
	_translate()


func bind_favorites(store: CityFavorites) -> void:
	favorites = store
	favorites.changed.connect(_draw_rows)


func _favorite(row: Dictionary) -> bool:
	return favorites != null and favorites.contains(CityFavorites.local_key(row.path))


func bind_cloud(service: Node) -> void:
	cloud = service
	if cloud != null and cloud.has_signal("changed") and not cloud.changed.is_connected(_draw_rows.call_deferred):
		cloud.changed.connect(_draw_rows.call_deferred)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(native_list):
		_translate()
		_draw_rows()


func _translate() -> void:
	for column in columns:
		set_column_title(column, tr(TITLES[column]))
	set_column_title(0, "")


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _job_signature == _native_signature():
			_rows = _results
			_draw_rows()
		else:
			_signature.clear()
	if not dialog.visible:
		_cancel_read()
		return
	var detailed := dialog.display_mode == FileDialog.DISPLAY_LIST
	visible = detailed
	native_list.visible = not detailed
	_elapsed += delta
	_metadata_age += delta
	if not detailed or _elapsed < 0.15:
		return
	_elapsed = 0.0
	var signature := _native_signature()
	if signature == _signature and _metadata_age < 5.0:
		return
	if _task >= 0:
		_cancel_read()
		clear()
		_rows.clear()
		_signature.clear()
		return
	_signature = signature
	_metadata_age = 0.0
	_job_signature = signature.duplicate()
	_rows.clear()
	for i in native_list.item_count:
		var name := native_list.get_item_text(i)
		var path := dialog.current_dir.path_join(name).simplify_path()
		_rows.append({"name": name, "path": path, "index": i, "directory": DirAccess.dir_exists_absolute(path)})
	_draw_rows()
	_mutex.lock()
	_cancelled = false
	_mutex.unlock()
	_task = WorkerThreadPool.add_task(_read_rows.bind(_rows.duplicate(true)))


func _native_signature() -> Array:
	var signature: Array = [dialog.current_dir]
	for i in native_list.item_count:
		signature.append(native_list.get_item_text(i))
	return signature


func _read_rows(rows: Array[Dictionary]) -> void:
	for row in rows:
		_mutex.lock()
		var cancelled := _cancelled
		_mutex.unlock()
		if cancelled:
			break
		if row.directory:
			continue
		row.modified = FileAccess.get_modified_time(row.path)
		if str(row.path).get_extension().to_lower() == "sc2x":
			var archive := CityPreviewStore.read_members(row.path, {
				Sc2xDocument.METADATA_ENTRY: 1024 * 1024,
				CityPreviewInfo.MULTIPLAYER_ENTRY: CityPreviewInfo.MAX_MULTIPLAYER_BYTES,
			})
			var info := CityPreviewInfo.from_archive(archive)
			if not info.is_empty():
				row.multiplayer = info.multiplayer
				row.expanded = info.expanded
				if archive.sizes.has(RegionCampaign.ENTRY) or info.get("mode") == "region":
					row.region = true
				elif not info.multiplayer or info.get("mode", "unknown") != "unknown":
					row.region = false
			else:
				var file := FileAccess.open(row.path, FileAccess.READ)
				if file != null and file.get_buffer(4).get_string_from_ascii() == "FORM":
					row.multiplayer = false
					row.region = false
					row.expanded = false
		elif str(row.path).get_extension().to_lower() in ["sc2", "scn", "cty"]:
			row.multiplayer = false
			row.region = false
			row.expanded = false
	_results = rows


func _draw_rows() -> void:
	if not is_instance_valid(native_list):
		return
	# Restoring the highlighted row is presentation only. Emitting selection
	# here would overwrite a filename the player has typed since selecting it.
	var was_blocking := is_blocking_signals()
	set_block_signals(true)
	clear()
	var root := create_item()
	var rows := _rows.duplicate()
	for row: Dictionary in rows:
		if int(row.index) >= native_list.item_count or native_list.get_item_text(row.index) != row.name:
			_signature.clear()
			set_block_signals(was_blocking)
			return
		row.cloud = int(cloud.local_availability(row.path)) if cloud != null and cloud.has_method("local_availability") else -1
	rows.sort_custom(_before)
	for row: Dictionary in rows:
		var item := create_item(root)
		item.set_auto_translate_mode(1, Node.AUTO_TRANSLATE_MODE_DISABLED)
		item.set_text(1, row.name)
		item.set_metadata(0, row.index)
		item.set_metadata(1, row.path)
		item.set_icon(1, native_list.get_item_icon(row.index))
		item.set_icon_modulate(1, native_list.get_item_icon_modulate(row.index))
		if not row.directory:
			item.add_button(0, FILLED_STAR if _favorite(row) else STAR, 0, false, tr("Remove from favorites") if _favorite(row) else tr("Add to favorites"))
		if row.get("modified", 0) > 0:
			item.set_text(2, format_timestamp(row.modified))
		if not row.directory:
			item.set_text(3, tr("Multiplayer") if row.get("multiplayer", false) else (tr("Single-player") if row.has("multiplayer") else tr("Unknown")))
			item.set_text(4, tr("Yes") if row.get("region", false) else (tr("No") if row.has("region") else tr("Unknown")))
			item.set_text(5, tr("Expanded") if row.get("expanded", false) else (tr("Classic") if row.has("expanded") else tr("Unknown")))
			var availability: int = row.cloud
			if not scenario_mode:
				item.set_text(6, tr("Yes") if availability == 1 else (tr("No") if availability == 0 else tr("Unknown")))
				item.set_tooltip_text(6, tr("Cloud availability refers to the linked save in the current account."))
		if native_list.is_selected(row.index):
			item.select(0)
			ensure_cursor_is_visible()
	_refresh_star_colors()
	set_block_signals(was_blocking)


func _refresh_star_colors() -> void:
	if get_root() == null:
		return
	var item := get_root().get_first_child()
	while item != null:
		if item.get_button_count(0) > 0:
			var starred := favorites != null and favorites.contains(CityFavorites.local_key(str(item.get_metadata(1))))
			item.set_button(0, 0, FILLED_STAR if starred else STAR)
			item.set_button_color(0, 0, get_theme_color("font_selected_color" if item == get_selected() else "font_color"))
		item = item.get_next()


func set_scenario_mode(enabled: bool) -> void:
	scenario_mode = enabled
	clear()
	columns = TITLES.size() - int(enabled)
	if _sort_column >= columns:
		_sort_column = 1
	_translate()
	_draw_rows()


func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.directory != b.directory:
		return a.directory
	var left: Variant = a.name
	var right: Variant = b.name
	if _sort_column == 0:
		left = int(not _favorite(a))
		right = int(not _favorite(b))
	elif _sort_column == 2:
		left = a.get("modified", 0)
		right = b.get("modified", 0)
	elif _sort_column in [3, 4, 5]:
		var key := "multiplayer" if _sort_column == 3 else "region" if _sort_column == 4 else "expanded"
		left = int(a.get(key, -1))
		right = int(b.get(key, -1))
	elif _sort_column == 6:
		left = a.cloud
		right = b.cloud
	if left == right:
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
	var before: bool = str(left).naturalnocasecmp_to(str(right)) < 0 if left is String else left < right
	return not before if _descending else before


func _sort(column: int, _mouse_button: int) -> void:
	_descending = not _descending if column == _sort_column else false
	_sort_column = column
	_draw_rows()


func _selected() -> void:
	if _signature != _native_signature():
		return
	var item := get_selected()
	if item == null:
		return
	_refresh_star_colors()
	var index := int(item.get_metadata(0))
	native_list.deselect_all()
	native_list.select(index)
	native_list.item_selected.emit(index)


func _activated() -> void:
	if _signature != _native_signature():
		return
	var item := get_selected()
	if item != null:
		native_list.item_activated.emit(int(item.get_metadata(0)))


func _star_clicked(item: TreeItem, _column: int, _id: int, mouse: int) -> void:
	if mouse != MOUSE_BUTTON_LEFT or _signature != _native_signature() or favorites == null:
		return
	var key := CityFavorites.local_key(str(item.get_metadata(1)))
	# Redraw after the Tree finishes handling this button's input.
	favorites.set_favorite.call_deferred(key, not favorites.contains(key))


func _context_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := get_item_at_position(event.position)
	if item == null or _signature != _native_signature():
		return
	item.select(1)
	_selected()
	_open_context(str(item.get_metadata(1)), Vector2i(get_screen_position() + event.position))
	accept_event()


func _native_context_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var index := native_list.get_item_at_position(event.position, true)
	if index < 0:
		return
	native_list.deselect_all()
	native_list.select(index)
	native_list.item_selected.emit(index)
	_open_context(dialog.current_dir.path_join(native_list.get_item_text(index)).simplify_path(), Vector2i(native_list.get_screen_position() + event.position))
	native_list.accept_event()


func _open_context(path: String, screen_position: Vector2i) -> void:
	_context_path = path
	_context_signature = _native_signature()
	context.clear()
	context.add_item(tr("Open"), 0)
	if not DirAccess.dir_exists_absolute(_context_path):
		context.add_item(tr("Remove from favorites") if favorites != null and favorites.contains(CityFavorites.local_key(_context_path)) else tr("Add to favorites"), 1)
		var available := int(cloud.local_availability(_context_path)) if cloud != null else -1
		if available != 1 and not scenario_mode:
			context.add_item(tr("Upload to Cloud"), 2)
			context.set_item_disabled(context.get_item_index(2), cloud == null or not _rows.any(func(row: Dictionary) -> bool: return row.path == _context_path and row.has("multiplayer") and not row.multiplayer and str(row.path).get_extension().to_lower() != "cty"))
	context.add_separator()
	context.add_item(tr("Show in file manager"), 3)
	context.add_item(tr("Copy path"), 4)
	context.position = screen_position
	context.popup()


func _context_action(id: int) -> void:
	if _context_signature != _native_signature() or not dialog.visible:
		return
	var path := _context_path
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		return
	match id:
		0:
			for index in native_list.item_count:
				if dialog.current_dir.path_join(native_list.get_item_text(index)).simplify_path() == path:
					native_list.item_activated.emit(index)
					break
		1:
			var key := CityFavorites.local_key(path)
			favorites.set_favorite(key, not favorites.contains(key))
		2:
			upload_requested.emit(path)
		3:
			OS.shell_show_in_file_manager(path)
		4:
			DisplayServer.clipboard_set(path)


func _exit_tree() -> void:
	_cancel_read()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


func _cancel_read() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()
