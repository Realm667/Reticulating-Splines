class_name NewspaperReader
extends Control
## The full text of one story above the newspaper. A click outside the panel,
## the close button or Escape closes it.

const BACKDROP := Color(0.0, 0.0, 0.0, 0.6)
const PAPER := NewspaperPage.PAPER
const BORDER := Color("#555555")
const INK := NewspaperStory.INK
const MAX_WIDTH := 720.0
const AREA_SHARE := Vector2(0.9, 0.85)
const PADDING := 24.0
const TITLE_SIZE := 24
const TITLE_LINE := 28.0
const TITLE_SIDE := 30.0
const TITLE_GAP := 22.0
const TEXT_SIZE := 15
const TEXT_LINE := 18.75
const SCROLL_GAP := 16
const CLOSE_SIZE := Vector2(28.0, 28.0)
const CLOSE_MARGIN := 10.0

var panel: Panel
var title_label: Label
var text_label: Label
var scroll: ScrollContainer
var close_button: Button


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	panel = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = BORDER
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var fibers := TextureRect.new()
	fibers.texture = NewspaperPage.newsprint()
	fibers.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fibers.stretch_mode = TextureRect.STRETCH_SCALE
	fibers.modulate = NewspaperPage.PAPER_TINT
	fibers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fibers)
	fibers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fibers.offset_left = 1
	fibers.offset_top = 1
	fibers.offset_right = -1
	fibers.offset_bottom = -1

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_override("font", NewspaperFonts.headline())
	title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	title_label.add_theme_color_override("font_color", INK)
	panel.add_child(title_label)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 10
	for style_name in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color = Color("735b3d", 0.14 if style_name.begins_with("scroll") else 0.48 if style_name == "grabber" else 0.72)
		bar_style.set_corner_radius_all(3)
		bar_style.content_margin_left = 5
		bar_style.content_margin_right = 5
		bar_style.content_margin_top = 12 if not style_name.begins_with("scroll") else 0
		bar_style.content_margin_bottom = bar_style.content_margin_top
		bar.add_theme_stylebox_override(style_name, bar_style)
	var text_margin := MarginContainer.new()
	text_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_margin.add_theme_constant_override("margin_right", SCROLL_GAP)
	scroll.add_child(text_margin)

	text_label = Label.new()
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_FILL
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_override("font", NewspaperFonts.body())
	text_label.add_theme_font_size_override("font_size", TEXT_SIZE)
	text_label.add_theme_color_override("font_color", INK)
	text_label.add_theme_constant_override("line_spacing",
		int(TEXT_LINE - NewspaperFonts.body().get_height(TEXT_SIZE)))
	text_margin.add_child(text_label)

	close_button = Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "Close article"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.add_theme_font_override("font", NewspaperFonts.interface())
	close_button.add_theme_font_size_override("font_size", NewspaperPage.CLOSE_FONT_SIZE)

	for color_name in ["font_color", "font_hover_color", "font_pressed_color"]:
		close_button.add_theme_color_override(color_name, INK)

	var hover := StyleBoxFlat.new()
	hover.bg_color = NewspaperPage.CLOSE_HOVER
	close_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	close_button.add_theme_stylebox_override("hover", hover)
	close_button.add_theme_stylebox_override("pressed", hover)
	close_button.pressed.connect(hide)
	panel.add_child(close_button)
	resized.connect(layout)


func open(title: String, text: String) -> void:
	title_label.text = title
	text_label.text = pre_line(text)
	scroll.scroll_vertical = 0
	show()
	layout()


# keeps line breaks and collapses other white space, like CSS pre-line
static func pre_line(text: String) -> String:
	var lines := PackedStringArray()

	for line in text.split("\n"):
		lines.append(NewspaperStory.collapse_spaces(line))

	return "\n".join(lines)


func layout() -> void:
	var width := minf(MAX_WIDTH, size.x * AREA_SHARE.x)
	var inner := width - PADDING * 2.0
	title_label.size.x = maxf(1.0, inner - TITLE_SIDE * 2.0)
	var title_height := ceilf(title_label.get_minimum_size().y)
	text_label.size.x = maxf(1.0, inner - SCROLL_GAP)
	var text_height := ceilf(text_label.get_minimum_size().y)
	var chrome := PADDING * 2.0 + title_height + TITLE_GAP
	var maximum := floorf(size.y * AREA_SHARE.y)
	var needs_scroll := text_height > maxf(0.0, maximum - chrome)
	# Measure with the same font, spacing and width as the visible Label.
	# A speculative scrollbar must not narrow a fitting article into overflow.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS if needs_scroll else ScrollContainer.SCROLL_MODE_DISABLED
	if needs_scroll:
		text_label.size.x = maxf(1.0, inner - SCROLL_GAP - scroll.get_v_scroll_bar().get_combined_minimum_size().x)
		text_height = ceilf(text_label.get_minimum_size().y)
	var height := minf(maximum, chrome + text_height)
	panel.size = Vector2(width, height)
	panel.position = ((size - panel.size) / 2.0).round()
	title_label.position = Vector2(PADDING + TITLE_SIDE, PADDING)
	title_label.size = Vector2(inner - TITLE_SIDE * 2.0, title_height)
	scroll.position = Vector2(PADDING, PADDING + title_height + TITLE_GAP)
	scroll.size = Vector2(inner, maxf(0.0, height - scroll.position.y - PADDING))
	close_button.position = Vector2(width - CLOSE_MARGIN - CLOSE_SIZE.x, CLOSE_MARGIN)
	close_button.size = CLOSE_SIZE


func _text_height(text: String, font: Font, font_size: int, width: float, line_height: float) -> float:
	if text.is_empty():
		return 0.0

	var paragraph := TextParagraph.new()
	paragraph.width = maxf(1.0, width)
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.add_string(text, font, font_size)

	return paragraph.get_line_count() * line_height + 1.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)


func _gui_input(event: InputEvent) -> void:
	# a click on the backdrop closes the story
	if event is InputEventMouseButton and event.pressed and not panel.get_rect().has_point(event.position):
		accept_event()
		hide()
