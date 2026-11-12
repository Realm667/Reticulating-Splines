class_name CityCloudList
extends CityLibraryTable
## Table adapter for CloudPanel's version, account and conflict workflow.

const TITLES := ["Favorite", "City name", "Date modified", "Game mode", "Expanded", "Status"]
var panel: CloudPanel
var favorites: CityFavorites
var _drawing := false
var _sort_column := 1
var _descending := false
var menu: PopupMenu
var _context_id := ""
var _context_key := ""


func configure(owner_panel: CloudPanel, store: CityFavorites) -> void:
	panel = owner_panel
	favorites = store
	columns = TITLES.size()
	column_titles_visible = true
	hide_root = true
	select_mode = Tree.SELECT_ROW
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 140
	set_column_expand(0, false)
	for col in columns:
		set_column_custom_minimum_width(col, [40, 160, 135, 100, 85, 140][col])
		set_column_clip_content(col, true)
	item_selected.connect(_selected)
	item_activated.connect(_activated)
	button_clicked.connect(_star_clicked)
	column_title_clicked.connect(func(col: int, _mouse: int) -> void:
		_descending = not _descending if col == _sort_column else false
		_sort_column = col
		refresh())
	gui_input.connect(_context_input)
	menu = PopupMenu.new()
	add_child(menu)
	menu.id_pressed.connect(_context_action)
	favorites.changed.connect(refresh)
	theme_changed.connect(refresh.call_deferred)
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and panel != null:
		refresh()


func refresh() -> void:
	_drawing = true
	clear()
	for col in columns:
		set_column_title(col, tr(TITLES[col]))
	set_column_title(0, "")
	var root := create_item()
	var indices := range(panel.save_rows.size())
	indices.sort_custom(_before)
	for index in indices:
		var row: Dictionary = panel.save_rows[index]
		var item := create_item(root)
		var key := CityFavorites.cloud_key(panel.sync, str(row.get("id", "")))
		item.set_metadata(0, {"index": index, "id": row.get("id", ""), "key": key})
		item.add_button(0, CitySaveList.STAR, 0, key.is_empty(), tr("Remove from favorites") if favorites.contains(key) else tr("Add to favorites"))
		item.set_button_color(0, 0, Color("f5cd62") if favorites.contains(key) else get_theme_color("font_color"))
		item.set_auto_translate_mode(1, Node.AUTO_TRANSLATE_MODE_DISABLED)
		item.set_text(1, str(row.get("name", "")))
		item.set_text(2, format_timestamp(row.get("updated_at")))
		var kind := str(row.get("metadata", {}).get("kind", ""))
		item.set_text(3, tr("Multiplayer") if kind == "multiplayer" else tr("Single-player") if kind in ["city", "region"] else tr("Unknown"))
		var expanded: Variant = panel.sync.cloud_expanded(str(row.get("id", "")), str(row.get("head", ""))) if panel.sync != null and panel.sync.has_method("cloud_expanded") else null
		if str(row.get("metadata", {}).get("save_format", "")) == "sc2":
			expanded = false
		item.set_text(4, tr("Unknown") if expanded == null else tr("Expanded") if expanded else tr("Classic"))
		item.set_text(5, tr(panel._save_status(row)))
		if str(row.get("id", "")) == panel.selected_save:
			item.select(1)
	_refresh_star_colors()
	_drawing = false


func _refresh_star_colors() -> void:
	if get_root() == null:
		return
	var item := get_root().get_first_child()
	while item != null:
		var key := str(item.get_metadata(0).key)
		item.set_button_color(0, 0, Color("f5cd62") if favorites.contains(key) else get_theme_color("font_selected_color" if item == get_selected() else "font_color"))
		item = item.get_next()


func _before(a: int, b: int) -> bool:
	var left: Dictionary = panel.save_rows[a]
	var right: Dictionary = panel.save_rows[b]
	var comparison := 0
	if _sort_column == 0:
		comparison = int(favorites.contains(CityFavorites.cloud_key(panel.sync, str(right.get("id", ""))))) - int(favorites.contains(CityFavorites.cloud_key(panel.sync, str(left.get("id", "")))))
	elif _sort_column == 2:
		comparison = str(left.get("updated_at", "")).naturalnocasecmp_to(str(right.get("updated_at", "")))
	elif _sort_column == 3:
		comparison = str(left.get("metadata", {}).get("kind", "")).naturalnocasecmp_to(str(right.get("metadata", {}).get("kind", "")))
	elif _sort_column == 4:
		var left_rules: Variant = panel.sync.cloud_expanded(str(left.get("id", "")), str(left.get("head", ""))) if panel.sync.has_method("cloud_expanded") else null
		var right_rules: Variant = panel.sync.cloud_expanded(str(right.get("id", "")), str(right.get("head", ""))) if panel.sync.has_method("cloud_expanded") else null
		comparison = (int(left_rules) if left_rules != null else -1) - (int(right_rules) if right_rules != null else -1)
	elif _sort_column == 5:
		comparison = tr(panel._save_status(left)).naturalnocasecmp_to(tr(panel._save_status(right)))
	if comparison == 0:
		comparison = str(left.get("name", "")).naturalnocasecmp_to(str(right.get("name", "")))
	return comparison > 0 if _descending else comparison < 0


func _selected() -> void:
	if _drawing:
		return
	_refresh_star_colors()
	var item := get_selected()
	if item == null:
		return
	var data: Dictionary = item.get_metadata(0)
	if int(data.index) >= panel.save_rows.size() or panel.save_rows[data.index].id != data.id:
		return
	panel.saves.select(data.index)
	panel._select_save(data.index)


func _activated() -> void:
	var item := get_selected()
	if item != null:
		panel._activate_save(int(item.get_metadata(0).index))


func _star_clicked(item: TreeItem, _column: int, _id: int, mouse: int) -> void:
	if mouse != MOUSE_BUTTON_LEFT:
		return
	var key := str(item.get_metadata(0).key)
	if not key.is_empty():
		favorites.set_favorite.call_deferred(key, not favorites.contains(key))


func _context_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := get_item_at_position(event.position)
	if item == null:
		return
	var data: Dictionary = item.get_metadata(0)
	_context_id = str(data.id)
	_context_key = str(data.key)
	menu.clear()
	menu.add_item(tr("Open"), 0)
	menu.add_item(tr("Remove from favorites") if favorites.contains(_context_key) else tr("Add to favorites"), 1)
	menu.set_item_disabled(1, _context_key.is_empty())
	menu.position = Vector2i(get_screen_position() + event.position)
	menu.popup()
	accept_event()


func _context_action(id: int) -> void:
	for index in panel.save_rows.size():
		var row: Dictionary = panel.save_rows[index]
		if str(row.get("id", "")) != _context_id or CityFavorites.cloud_key(panel.sync, _context_id) != _context_key:
			continue
		if id == 0:
			panel._activate_save(index)
		elif id == 1:
			favorites.set_favorite(_context_key, not favorites.contains(_context_key))
		break
