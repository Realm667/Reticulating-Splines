class_name AnnualNewspaperDialog
extends AcceptDialog
## The latest completed year, presented as a separate newspaper edition.

signal location_requested(point: Vector2i)

var _review: AnnualCityReview
var _page: VBoxContainer


func _ready() -> void:
	title = "Annual review"
	transient = true
	exclusive = true
	get_ok_button().text = "Close"
	get_label().hide()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var paper := PanelContainer.new()
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var surface := StyleBoxFlat.new()
	surface.bg_color = NewspaperPage.PAPER
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		surface.set_content_margin(side, 16)
	paper.add_theme_stylebox_override("panel", surface)
	scroll.add_child(paper)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 10)
	paper.add_child(_page)


func open(review: AnnualCityReview) -> void:
	_review = review
	_rebuild()
	var area := get_parent().get_viewport().get_visible_rect().size
	popup_centered(Vector2i(mini(680, int(area.x * 0.88)), mini(510, int(area.y * 0.86))))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and visible and _review != null and _page != null:
		_rebuild()


func _rebuild() -> void:
	for child in _page.get_children():
		_page.remove_child(child)
		child.queue_free()
	var edition := _review.edition()
	_add_label(_review.city.display_name(), 24)
	_add_label(tr("Annual review %d") % int(edition.year), 17)
	_page.add_child(HSeparator.new())

	if edition.start >= 0 and edition.end >= 0:
		var change: int = edition.end - edition.start
		if change > 0:
			_add_label(tr("The city gained %s residents") % DisplayNumberFormat.format(change), 21)
		elif change < 0:
			_add_label(tr("The city lost %s residents") % DisplayNumberFormat.format(-change), 21)
		_add_label(tr("Population: %s → %s") % [DisplayNumberFormat.format(int(edition.start)),
			DisplayNumberFormat.format(int(edition.end))])
	elif edition.end >= 0:
		_add_label(tr("Year-end population: %s") % DisplayNumberFormat.format(int(edition.end)))
	if edition.has("budget"):
		_add_label(tr("Annual budget balance: %s") % BudgetReport.currency(int(edition.budget)))
	if edition.start < 0 or edition.end < 0 or not edition.has("budget"):
		_add_label(tr("Some annual figures are unavailable."))

	_page.add_child(HSeparator.new())
	_add_label(tr("Events of the year"), 19)
	if edition.events.is_empty():
		_add_label(tr("No events were recorded for this year."))
	for item: Dictionary in edition.events:
		var month := tr(BudgetReport.MONTHS[item.month])
		var story := (tr("%s: %s was built.") % [month, tr(BuildingConstants.DEFAULT_MICROSIM_LABELS[item.id])]
			if item.kind == "building" else tr("%s: %s struck the city.") % [month, tr(CityMenuBar.disaster_name(item.id))])
		_add_label(story)
		var point := _review.point_in_current_view(item)
		if point.x < 0:
			continue
		var locate := Button.new()
		locate.text = "Show on map"
		locate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		locate.pressed.connect(func() -> void:
			hide()
			location_requested.emit(_review.point_in_current_view(item)))
		_page.add_child(locate)


func _add_label(value: String, font_size := 16) -> void:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", NewspaperPage.INK)
	label.add_theme_font_size_override("font_size", font_size)
	_page.add_child(label)
