class_name CitySaveList
extends Tree
## A detailed view of the native file list, retaining its navigation and selection.

const TITLES := ["File name", "Date modified", "Game mode", "Multi-region", "Cloud"]
var dialog: FileDialog
var native_list: ItemList
var cloud: Node
var _signature: Array = []
var _job_signature: Array = []
var _task := -1
var _results: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _elapsed := 0.0
var _metadata_age := 0.0
var _cancelled := false
var _mutex := Mutex.new()
var _sort_column := 0
var _descending := false


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
	set_column_expand_ratio(0, 3)
	for column in columns:
		set_column_custom_minimum_width(column, [180, 145, 110, 120, 70][column])
		set_column_clip_content(column, true)
	for column in range(1, columns):
		set_column_expand_ratio(column, 1)
	item_selected.connect(_selected)
	item_activated.connect(_activated)
	column_title_clicked.connect(_sort)
	dialog.visibility_changed.connect(func() -> void: _signature.clear())
	_translate()


func bind_cloud(service: Node) -> void:
	cloud = service
	if cloud != null and cloud.has_signal("changed") and not cloud.changed.is_connected(_draw_rows):
		cloud.changed.connect(_draw_rows)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(native_list):
		_translate()
		_draw_rows()


func _translate() -> void:
	for column in columns:
		set_column_title(column, tr(TITLES[column]))


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
				if archive.sizes.has(RegionCampaign.ENTRY) or info.get("mode") == "region":
					row.region = true
				elif not info.multiplayer or info.get("mode", "unknown") != "unknown":
					row.region = false
			else:
				var file := FileAccess.open(row.path, FileAccess.READ)
				if file != null and file.get_buffer(4).get_string_from_ascii() == "FORM":
					row.multiplayer = false
					row.region = false
		elif str(row.path).get_extension().to_lower() in ["sc2", "scn", "cty"]:
			row.multiplayer = false
			row.region = false
	_results = rows


func _draw_rows() -> void:
	if not is_instance_valid(native_list):
		return
	clear()
	var root := create_item()
	var rows := _rows.duplicate()
	for row: Dictionary in rows:
		if int(row.index) >= native_list.item_count or native_list.get_item_text(row.index) != row.name:
			_signature.clear()
			return
		row.cloud = int(cloud.local_availability(row.path)) if cloud != null and cloud.has_method("local_availability") else -1
	rows.sort_custom(_before)
	for row: Dictionary in rows:
		var item := create_item(root)
		item.set_auto_translate_mode(0, Node.AUTO_TRANSLATE_MODE_DISABLED)
		item.set_text(0, row.name)
		item.set_metadata(0, row.index)
		item.set_icon(0, native_list.get_item_icon(row.index))
		if row.get("modified", 0) > 0:
			var date := Time.get_datetime_dict_from_unix_time(int(row.modified) + Time.get_time_zone_from_system().bias * 60)
			item.set_text(1, "%04d-%02d-%02d %02d:%02d" % [date.year, date.month, date.day, date.hour, date.minute])
		if not row.directory:
			item.set_text(2, tr("Multiplayer") if row.get("multiplayer", false) else (tr("Single-player") if row.has("multiplayer") else tr("Unknown")))
			item.set_text(3, tr("Yes") if row.get("region", false) else (tr("No") if row.has("region") else tr("Unknown")))
			var availability: int = row.cloud
			item.set_text(4, tr("Yes") if availability == 1 else (tr("No") if availability == 0 else tr("Unknown")))
			item.set_tooltip_text(4, tr("Cloud availability refers to the linked save in the current account."))
		if native_list.is_selected(row.index):
			item.select(0)
			ensure_cursor_is_visible()


func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.directory != b.directory:
		return a.directory
	var left: Variant = a.name
	var right: Variant = b.name
	if _sort_column == 1:
		left = a.get("modified", 0)
		right = b.get("modified", 0)
	elif _sort_column in [2, 3]:
		left = int(a.get("multiplayer" if _sort_column == 2 else "region", -1))
		right = int(b.get("multiplayer" if _sort_column == 2 else "region", -1))
	elif _sort_column == 4:
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


func _exit_tree() -> void:
	_cancel_read()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


func _cancel_read() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()
