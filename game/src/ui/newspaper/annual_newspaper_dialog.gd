class_name AnnualNewspaperDialog
extends Window
## An archival newspaper spread covering the last ten completed city years.

signal location_requested(point: Vector2i)

const INK := Color("#382719")
const PAPER := Color("#f1e3c8")
const ACCENT := Color("#712c27")
const PAPER_ART = preload("res://assets/ui/charter/paper.png")
const ENGRAVING_ART = preload("res://assets/ui/charter/engraving.png")
const TOWN_ART = preload("res://assets/ui/charter/town-vignette.png")
const SEAL_ART = preload("res://assets/ui/charter/seal.png")
const PRINT_SHADER = preload("res://src/ui/newspaper/paper_ink.gdshader")

var _review: AnnualCityReview
var _page: VBoxContainer
var _years: OptionButton
var _stories: VBoxContainer
var _heading: Label
var _range: Label
var _summary: Label
var _previous: Button
var _next: Button
var _signature: Label
var _left_view: TextureRect
var _right_view: TextureRect
var _editions: Array[Dictionary] = []


func _ready() -> void:
	title = "City chronicle"
	transient = true
	exclusive = true
	borderless = true
	transparent = true
	transparent_bg = true
	visible = false
	close_requested.connect(hide)
	var background := _art(PAPER_ART, Rect2(36, 8, 1520, 976), Vector2.ZERO)
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var paper := PanelContainer.new()
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var surface := StyleBoxEmpty.new()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		surface.set_content_margin(side, 52 if side in [SIDE_LEFT, SIDE_RIGHT] else 24)
	paper.add_theme_stylebox_override("panel", surface)
	add_child(paper)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 6)
	paper.add_child(_page)
	var top := HBoxContainer.new()
	_page.add_child(top)
	_left_view = _art(TOWN_ART, Rect2(Vector2.ZERO, TOWN_ART.get_size()), Vector2(190, 82), true)
	top.add_child(_left_view)
	var masthead := VBoxContainer.new()
	masthead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead.add_theme_constant_override("separation", 0)
	top.add_child(masthead)
	var crest := _art(ENGRAVING_ART, Rect2(780, 0, 610, 370), Vector2(76, 46), true)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	masthead.add_child(crest)
	_heading = _label("The City Chronicle", 38, NewspaperFonts.masthead(0))
	_heading.add_theme_color_override("font_color", ACCENT)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	masthead.add_child(_heading)
	_range = _label("", 13, NewspaperFonts.body_bold())
	_range.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	masthead.add_child(_range)
	_right_view = _art(TOWN_ART, Rect2(Vector2.ZERO, TOWN_ART.get_size()), Vector2(190, 82), true)
	_right_view.flip_h = true
	top.add_child(_right_view)
	var close := _button("×", hide)
	close.tooltip_text = "Close"
	close.custom_minimum_size = Vector2(44, 38)
	close.add_theme_font_size_override("font_size", 20)
	close.get_theme_stylebox("normal").bg_color = PAPER
	var chrome := Control.new()
	chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chrome)
	chrome.add_child(close)
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -70
	close.offset_right = -26
	close.offset_top = 24
	close.offset_bottom = 62
	_rule(2)
	var lead := HBoxContainer.new()
	_page.add_child(lead)
	var decade := _label("10", 32, NewspaperFonts.body_italic())
	decade.autowrap_mode = TextServer.AUTOWRAP_OFF
	decade.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lead.add_theme_constant_override("separation", 14)
	decade.add_theme_color_override("font_color", ACCENT)
	lead.add_child(decade)
	var caption := VBoxContainer.new()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.add_child(caption)
	caption.add_child(_label("YEARS OF CITY HISTORY", 11))
	_summary = _label("", 17, NewspaperFonts.body_bold())
	caption.add_child(_summary)
	_rule(1)
	var navigation := HBoxContainer.new()
	_page.add_child(navigation)
	_previous = _button("‹", func() -> void: _select_year(_years.selected - 1))
	_previous.tooltip_text = "Previous year"
	navigation.add_child(_previous)
	_years = OptionButton.new()
	_years.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_years.custom_minimum_size.y = 32
	_style_button(_years)
	var popup := _years.get_popup()
	var popup_paper := StyleBoxFlat.new()
	popup_paper.bg_color = PAPER
	popup.add_theme_stylebox_override("panel", popup_paper)
	var selected_year := StyleBoxFlat.new()
	selected_year.bg_color = ACCENT
	popup.add_theme_stylebox_override("hover", selected_year)
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", PAPER)
	popup.add_theme_font_override("font", NewspaperFonts.body())
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
	_stories.add_theme_constant_override("separation", 6)
	scroll.add_child(_stories)
	_rule(1)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	_page.add_child(footer)
	var footer_inset := Control.new()
	footer_inset.custom_minimum_size.x = 12
	footer.add_child(footer_inset)
	var note := _label("A record of the last ten completed years. Missing years are marked in the archive.", 11, NewspaperFonts.body_italic())
	note.add_theme_color_override("font_color", ACCENT)
	footer.add_child(note)
	_signature = _label("", 18, NewspaperFonts.body_italic())
	_signature.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_signature.custom_minimum_size.x = 120
	_signature.size_flags_horizontal = Control.SIZE_SHRINK_END
	_signature.tooltip_text = "Mayor"
	footer.add_child(_signature)
	footer.add_child(_art(SEAL_ART, Rect2(310, 70, 920, 920), Vector2(62, 62)))


func open(review: AnnualCityReview) -> void:
	_review = review
	_fit()
	_rebuild()
	popup_centered(size)


func _fit() -> void:
	var area := get_parent().get_viewport().get_visible_rect().size
	size = Vector2i(mini(1020, int(area.x * 0.94)), mini(640, int(area.y * 0.94)))
	_left_view.visible = size.x >= 820
	_right_view.visible = size.x >= 820


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
	_signature.text = _review.city.mayor_name() if not _review.city.mayor_name().is_empty() else tr("Mayor")
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
	var year_heading := _label(tr("The year %d") % int(edition.year), 20, NewspaperFonts.body_italic())
	year_heading.add_theme_color_override("font_color", ACCENT)
	_stories.add_child(year_heading)
	var figures := GridContainer.new()
	figures.columns = 4 if size.x >= 820 else 3 if size.x >= 620 else 2 if size.x >= 440 else 1
	figures.add_theme_constant_override("h_separation", 14)
	figures.add_theme_constant_override("v_separation", 6)
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
	var chronicles := GridContainer.new()
	chronicles.columns = 2 if size.x >= 620 else 1
	chronicles.add_theme_constant_override("h_separation", 20)
	chronicles.add_theme_constant_override("v_separation", 8)
	_stories.add_child(chronicles)
	_event_section(chronicles, edition, "disaster", tr("Disaster chronicle"), tr("No disasters recorded."))
	_event_section(chronicles, edition, "building", tr("Landmark buildings"), tr("No landmark buildings recorded."))
	(_stories.get_parent() as ScrollContainer).set_deferred("scroll_vertical", 0)


func _figure(parent: GridContainer, caption: String, value: String, help := "") -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 0)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.tooltip_text = help if not help.is_empty() else tr("Figures recorded at year end. Earlier statistics are not reconstructed.")
	parent.add_child(block)
	var title_label := _label(caption, 12)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(title_label)
	var amount := _label(value, 19, NewspaperFonts.body_bold())
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(amount)


func _event_section(parent: GridContainer, edition: Dictionary, kind: String, heading: String, empty: String) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 4)
	parent.add_child(section)
	var title_label := _label(heading, 18, NewspaperFonts.body_italic())
	title_label.add_theme_color_override("font_color", ACCENT)
	section.add_child(title_label)
	var found := false
	for item: Dictionary in edition.events:
		if item.kind != kind or (kind == "building" and item.id not in AnnualCityReview.FACILITIES):
			continue
		found = true
		var month := tr(BudgetReport.MONTHS[item.month])
		var headline := (tr("%s: %s was built.") % [month, tr(BuildingConstants.DEFAULT_MICROSIM_LABELS[item.id])]
			if kind == "building" else tr("%s: %s struck the city.") % [month, tr(CityMenuBar.disaster_name(item.id))])
		section.add_child(_label(headline, 15))
	if not found:
		section.add_child(_label(empty, 15))


func _rule(width: int) -> void:
	var rule := ColorRect.new()
	rule.color = ACCENT
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
	button.custom_minimum_size = Vector2(44, 32)
	button.pressed.connect(action)
	_style_button(button)
	return button


func _style_button(button: Button) -> void:
	button.add_theme_font_override("font", NewspaperFonts.body())
	button.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#d9c3a1") if state in ["hover", "pressed"] else Color.TRANSPARENT
		style.border_color = ACCENT
		style.set_border_width_all(1)
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state, style)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color, INK)
	button.add_theme_color_override("font_disabled_color", Color("#8a8170"))


func _art(texture: Texture2D, region: Rect2, minimum: Vector2, printed := false) -> TextureRect:
	var image := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	image.texture = atlas
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = minimum
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if printed:
		var print_ink := ShaderMaterial.new()
		print_ink.shader = PRINT_SHADER
		image.material = print_ink
	return image
