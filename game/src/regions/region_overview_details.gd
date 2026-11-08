class_name RegionOverviewDetails
extends VBoxContainer
## Read-only cards for the currently viewed city and its four neighbors.

# Retain the accessible textual summary for existing integrations.
var text := ""
var _signature := ""
var _neighbors: GridContainer


func _ready() -> void:
	resized.connect(_fit_columns)


func _fit_columns() -> void:
	if _neighbors != null:
		_neighbors.columns = 2 if size.x >= 430 else 1


func show_city(city: CityState) -> void:
	var data := SimNationWindowControl.snapshot(city)
	if not data.ok:
		return
	var rows: Array = []
	var lines: Array[String] = [data.city_name]
	for index in SimNationWindowControl.display_neighbor_indices(city.compass_rotation()):
		var neighbor: SimNationWindowControl.Neighbor = data.neighbors[index]
		var name := CityNeighbors.city_name(city, neighbor.index)
		rows.append([name, neighbor.population])
		lines.append(name)
	text = "\n".join(lines)
	var signature := str([data.city_name, data.display_population, data.national_population, rows, TranslationServer.get_locale()])
	if signature == _signature:
		return
	_signature = signature
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 10)
	var totals := HFlowContainer.new()
	add_child(totals)
	totals.add_child(_card(data.city_name, data.display_population, "Population", ReportIcons.MAP[4]))
	totals.add_child(_card(tr("National population"), data.national_population, "", ReportIcons.MAP[0]))
	var title := Label.new()
	title.text = "Neighbors"
	add_child(title)
	var neighbors := GridContainer.new()
	_neighbors = neighbors
	_fit_columns()
	neighbors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	neighbors.add_theme_constant_override("h_separation", 10)
	neighbors.add_theme_constant_override("v_separation", 10)
	add_child(neighbors)
	for index in rows.size():
		neighbors.add_child(_card(["↖", "↗", "↘", "↙"][index] + "  " + str(rows[index][0]), int(rows[index][1]), "Population"))


func _card(caption: String, value: int, unit: String, icon: Texture2D = null) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 160
	panel.theme_type_variation = &"UtilityPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	if icon != null:
		var symbol := TextureRect.new()
		symbol.texture = icon
		symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		symbol.custom_minimum_size = Vector2(28, 28)
		row.add_child(symbol)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var title := Label.new()
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.text = caption
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var number := Label.new()
	number.text = DisplayNumberFormat.format(value)
	number.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	number.add_theme_font_size_override("font_size", 21)
	column.add_child(number)
	if not unit.is_empty():
		var label := Label.new()
		label.text = unit
		label.add_theme_font_size_override("font_size", 12)
		column.add_child(label)
	return panel
