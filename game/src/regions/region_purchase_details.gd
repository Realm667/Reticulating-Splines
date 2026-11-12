class_name RegionPurchaseDetails
extends VBoxContainer
## Purchase facts share a grid, with terrain composition beneath the costs.

var _facts: GridContainer


func _ready() -> void:
	resized.connect(func() -> void:
		if _facts != null:
			_facts.columns = 2 if size.x >= 460 else 1)


func show_offer(quote: Dictionary, funds: int, administration: int) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_facts = GridContainer.new()
	_facts.columns = 2 if size.x >= 460 else 1
	_facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facts.add_theme_constant_override("h_separation", 10)
	_facts.add_theme_constant_override("v_separation", 10)
	add_child(_facts)
	_fact("Purchase price", BudgetReport.currency(int(quote.price)))
	_fact("Funds after purchase", BudgetReport.currency(funds - int(quote.price)))
	_fact("Additional administration", BudgetReport.currency(RegionRules.ANNUAL_ADMINISTRATION), "Per year")
	_fact("Annual administration after purchase", BudgetReport.currency(administration + RegionRules.ANNUAL_ADMINISTRATION), "Per year")
	var terrain := GridContainer.new()
	terrain.columns = 3
	terrain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain.add_theme_constant_override("h_separation", 12)
	add_child(terrain)
	var total := maxi(1, int(quote.flat) + int(quote.slope) + int(quote.water))
	for entry in [["Flat land", int(quote.flat), Color("99be72")], ["Slopes", int(quote.slope), Color("c6aa7c")], ["Water", int(quote.water), Color("77b7cf")]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		terrain.add_child(column)
		var label := Label.new()
		label.text = entry[0]
		column.add_child(label)
		var number := Label.new()
		number.text = "%s · %d%%" % [DisplayNumberFormat.format(entry[1]), roundi(float(entry[1]) / total * 100)]
		number.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		column.add_child(number)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.value = float(entry[1]) / total * 100
		bar.custom_minimum_size.y = 5
		var fill := StyleBoxFlat.new()
		fill.bg_color = entry[2]
		bar.add_theme_stylebox_override("fill", fill)
		column.add_child(bar)
	show()


func _fact(caption: String, value: String, unit := "") -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"UtilityPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facts.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = caption
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var number := Label.new()
	number.text = value
	number.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	number.add_theme_font_size_override("font_size", 21)
	column.add_child(number)
	if not unit.is_empty():
		var label := Label.new()
		label.text = unit
		label.theme_type_variation = &"HelpLabel"
		column.add_child(label)
