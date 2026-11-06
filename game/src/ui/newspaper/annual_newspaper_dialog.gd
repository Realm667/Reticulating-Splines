class_name AnnualNewspaperDialog
extends Window
## An archival newspaper spread covering the last ten completed city years.

signal location_requested(point: Vector2i)

const INK := Color("#25363a")
const PAPER := Color("#e6dfce")
const ACCENT := Color("#796135")

var _review: AnnualCityReview
var _page: VBoxContainer
var _years: OptionButton
var _stories: VBoxContainer
var _heading: Label
var _range: Label
var _summary: Label
var _previous: Button
var _next: Button
var _editions: Array[Dictionary] = []


func _ready() -> void:
	title = "City chronicle"
	transient = true
	exclusive = true
	borderless = true
	visible = false
	close_requested.connect(hide)
	var paper := PanelContainer.new()
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var surface := StyleBoxFlat.new()
	surface.bg_color = PAPER
	surface.border_color = INK
	surface.set_border_width_all(3)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		surface.set_content_margin(side, 22)
	paper.add_theme_stylebox_override("panel", surface)
	add_child(paper)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 9)
	paper.add_child(_page)
	var top := HBoxContainer.new()
	_page.add_child(top)
	var edition := _label("CITY ARCHIVE", 13)
	edition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(edition)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Close"
	close.custom_minimum_size = Vector2(44, 38)
	close.flat = true
	close.add_theme_color_override("font_color", INK)
	close.add_theme_color_override("font_hover_color", ACCENT)
	close.pressed.connect(hide)
	top.add_child(close)
	_heading = _label("The City Chronicle", 42, NewspaperFonts.masthead(0))
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(_heading)
	_range = _label("", 16)
	_range.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(_range)
	_rule(3)
	var lead := HBoxContainer.new()
	_page.add_child(lead)
	var decade := _label("10", 66, NewspaperFonts.headline())
	decade.autowrap_mode = TextServer.AUTOWRAP_OFF
	decade.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lead.add_theme_constant_override("separation", 24)
	decade.add_theme_color_override("font_color", ACCENT)
	lead.add_child(decade)
	var caption := VBoxContainer.new()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.add_child(caption)
	caption.add_child(_label("YEARS OF CITY HISTORY", 15))
	_summary = _label("", 23, NewspaperFonts.headline())
	caption.add_child(_summary)
	_rule(1)
	var navigation := HBoxContainer.new()
	_page.add_child(navigation)
	_previous = _button("‹", func() -> void: _select_year(_years.selected - 1))
	_previous.tooltip_text = "Previous year"
	navigation.add_child(_previous)
	_years = OptionButton.new()
	_years.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_years.custom_minimum_size.y = 40
	_style_button(_years)
	_years.item_selected.connect(_select_year)
	navigation.add_child(_years)
	_next = _button("›", func() -> void: _select_year(_years.selected + 1))
	_next.tooltip_text = "Next year"
	navigation.add_child(_next)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(scroll)
	_stories = VBoxContainer.new()
	_stories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stories.add_theme_constant_override("separation", 12)
	scroll.add_child(_stories)
	_rule(1)
	var note := _label("A record of the last ten completed years. Missing years are marked in the archive.", 13)
	note.add_theme_color_override("font_color", ACCENT)
	_page.add_child(note)


func open(review: AnnualCityReview) -> void:
	_review = review
	_fit()
	_rebuild()
	popup_centered(size)


func _fit() -> void:
	var area := get_parent().get_viewport().get_visible_rect().size
	size = Vector2i(mini(920, int(area.x * 0.9)), mini(740, int(area.y * 0.9)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and visible and _review != null and _page != null:
		_rebuild()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		hide()
		set_input_as_handled()


func _rebuild() -> void:
	_editions = _review.editions()
	_years.clear()
	for edition in _editions:
		_years.add_item(str(edition.year))
	_heading.text = tr("The City Chronicle")
	_range.text = _review.city.display_name() + ("  ·  %d – %d" % [_editions.front().year, _editions.back().year] if not _editions.is_empty() else "")
	var first_population: int = _editions.front().start if not _editions.is_empty() else -1
	var last_population: int = _editions.back().end if not _editions.is_empty() else -1
	_summary.text = (tr("Population: %s → %s") % [MultiplayerScoreboard.number(first_population),
		MultiplayerScoreboard.number(last_population)] if first_population >= 0 and last_population >= 0
		else tr("The story of your city, year by year"))
	_select_year(_editions.size() - 1)


func _select_year(index: int) -> void:
	if index < 0 or index >= _editions.size():
		return
	_years.select(index)
	_previous.disabled = index == 0
	_next.disabled = index == _editions.size() - 1
	for child in _stories.get_children():
		_stories.remove_child(child)
		child.queue_free()
	var edition := _editions[index]
	_stories.add_child(_label(tr("The year %d") % int(edition.year), 28, NewspaperFonts.headline()))
	var figures := GridContainer.new()
	figures.columns = 3 if size.x >= 700 else 2 if size.x >= 480 else 1
	figures.add_theme_constant_override("h_separation", 18)
	figures.add_theme_constant_override("v_separation", 12)
	figures.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stories.add_child(figures)
	var unavailable := tr("Not available")
	_figure(figures, tr("Population"), MultiplayerScoreboard.number(edition.end) if edition.end >= 0 else unavailable)
	_figure(figures, tr("Population change"), MultiplayerScoreboard.signed_number(edition.end - edition.start)
		if edition.start >= 0 and edition.end >= 0 else unavailable)
	var statistics: Dictionary = edition.get("statistics", {})
	var area := unavailable
	if statistics.has("developed") and statistics.get("tiles", 0) > 0:
		var percentage := String.num(100.0 * statistics.developed / statistics.tiles, 1)
		if TranslationServer.get_locale().get_slice("_", 0) in ["de", "es", "fr", "it", "pt"]:
			percentage = percentage.replace(".", ",")
		area = tr("%s tiles · %s%%") % [MultiplayerScoreboard.number(statistics.developed),
			percentage]
	_figure(figures, tr("Built-up area"), area, tr("Developed land includes buildings and infrastructure; trees and rubble are excluded."))
	_figure(figures, tr("Net wealth"), MultiplayerScoreboard.money(statistics.funds - statistics.debt)
		if statistics.has("funds") and statistics.has("debt") else unavailable, tr("Net wealth = city funds minus outstanding debt."))
	_figure(figures, tr("Funds"), MultiplayerScoreboard.money(statistics.funds) if statistics.has("funds") else unavailable)
	_figure(figures, tr("Debt"), MultiplayerScoreboard.money(statistics.debt) if statistics.has("debt") else unavailable)
	_figure(figures, tr("Year-end balance"), MultiplayerScoreboard.money(edition.budget) if edition.has("budget") else unavailable)
	_figure(figures, tr("City value"), MultiplayerScoreboard.money(statistics.city_value) if statistics.has("city_value") else unavailable)
	_figure(figures, tr("Education"), str(statistics.education) if statistics.has("education") else unavailable)
	_figure(figures, tr("Life expectancy"), tr("%s years") % str(statistics.life_expectancy) if statistics.has("life_expectancy") else unavailable)
	_figure(figures, tr("Unemployment"), str(statistics.unemployment) + "%" if statistics.has("unemployment") else unavailable)
	var note := _label(tr("Figures recorded at year end. Earlier statistics are not reconstructed."), 13)
	note.add_theme_color_override("font_color", ACCENT)
	_stories.add_child(note)
	_event_section(edition, "disaster", tr("Disaster chronicle"), tr("No disasters recorded."))
	_event_section(edition, "building", tr("Landmark buildings"), tr("No landmark buildings recorded."))
	(_stories.get_parent() as ScrollContainer).set_deferred("scroll_vertical", 0)


func _figure(parent: GridContainer, caption: String, value: String, help := "") -> void:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.tooltip_text = help
	parent.add_child(block)
	var title_label := _label(caption, 14)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(title_label)
	var amount := _label(value, 23, NewspaperFonts.headline())
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(amount)


func _event_section(edition: Dictionary, kind: String, heading: String, empty: String) -> void:
	_stories.add_child(_label(heading, 23, NewspaperFonts.headline()))
	var found := false
	for item: Dictionary in edition.events:
		if item.kind != kind or (kind == "building" and item.id not in AnnualCityReview.FACILITIES):
			continue
		found = true
		var month := tr(BudgetReport.MONTHS[item.month])
		var headline := (tr("%s: %s was built.") % [month, tr(BuildingConstants.DEFAULT_MICROSIM_LABELS[item.id])]
			if kind == "building" else tr("%s: %s struck the city.") % [month, tr(CityMenuBar.disaster_name(item.id))])
		_stories.add_child(_label(headline, 17))
	if not found:
		_stories.add_child(_label(empty, 16))


func _rule(width: int) -> void:
	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size.y = width
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(rule)


func _label(value: String, font_size: int, font: Font = null) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_override("font", font if font != null else NewspaperFonts.body())
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(44, 40)
	button.pressed.connect(action)
	_style_button(button)
	return button


func _style_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#d9cdb5") if state in ["hover", "pressed"] else PAPER
		style.border_color = ACCENT
		style.set_border_width_all(1)
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state, style)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color, INK)
	button.add_theme_color_override("font_disabled_color", Color("#8a8170"))
