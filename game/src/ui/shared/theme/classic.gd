class_name AppUiClassicTheme
extends RefCounted
## Opaque retro chrome. Artwork always comes from the selected graphics pack.

const FACE := Color("c0c0c0")
const SHADOW := Color("808080")
const NAVY := Color("000080")
static var _fonts: Dictionary[bool, Font] = {}


static func build(value: String) -> Theme:
	var dos := value == "classic_dos"
	var selection := Color.BLACK if dos else NAVY
	var result := ThemeDB.get_default_theme().duplicate(true) as Theme
	var regular := _font(dos)
	var bold := _font(true)
	result.default_font = regular
	result.default_font_size = 11
	# Replace inherited dark-engine colors, including less common native widgets.
	for type_name in result.get_type_list():
		for name in result.get_font_size_list(type_name):
			result.set_font_size(name, type_name, 11)
		for name in result.get_font_list(type_name):
			result.set_font(name, type_name, bold if "bold" in name or "title" in name else regular)
		for name in result.get_color_list(type_name):
			if name.begins_with("font") or name in ["default_color", "title_color", "caret_color"]:
				result.set_color(name, type_name, SHADOW if "disabled" in name or "placeholder" in name else Color.BLACK)
			if "outline" in name or "shadow" in name:
				result.set_color(name, type_name, Color.TRANSPARENT)
		for name in result.get_icon_list(type_name):
			result.set_icon(name, type_name, _ink_icon(result.get_icon(name, type_name)))
	for type_name in ["Label", "Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton", "PopupMenu", "LineEdit", "TextEdit", "Tree", "ItemList"]:
		result.set_font("font", type_name, regular)
		result.set_font_size("font_size", type_name, 11)
	result.set_font("title_font", "Window", bold)
	result.set_font_size("title_font_size", "Window", 11)
	result.set_color("title_color", "Window", Color.BLACK if dos else Color.WHITE)
	result.set_color("title_unfocused_color", "Window", Color.BLACK if dos else FACE)
	result.set_color("title_background", "AppPalette", FACE if dos else NAVY)
	result.set_color("default_color", "RichTextLabel", Color.BLACK)
	for name in ["normal_font", "italics_font", "mono_font"]:
		result.set_font(name, "RichTextLabel", regular)
	for name in ["bold_font", "bold_italics_font"]:
		result.set_font(name, "RichTextLabel", bold)

	var panel := flat(FACE, 8)
	for type_name in ["Panel", "PanelContainer", "AcceptDialog"]:
		result.set_stylebox("panel", type_name, panel)
	for type_name in ["PopupPanel", "TabContainer"]:
		result.set_stylebox("panel", type_name, bevel(FACE, false, 8))
	for type_name in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := bevel(FACE, state in ["pressed", "hover_pressed"], 5)
			result.set_stylebox(state, type_name, box)
			result.set_stylebox(state + "_mirrored", type_name, box)
		for name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			result.set_color(name, type_name, Color.BLACK)
	var focus := flat(Color.TRANSPARENT, 0)
	focus.border_color = Color.BLACK
	focus.set_border_width_all(1)
	for type_name in ["Button", "OptionButton", "LineEdit", "TextEdit", "ItemList", "Tree", "CheckBox", "CheckButton"]:
		result.set_stylebox("focus", type_name, focus)
	for type_name in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			result.set_stylebox(state, type_name, flat(Color.TRANSPARENT, 3))
		for name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "radio_checked", "radio_unchecked", "radio_checked_disabled", "radio_unchecked_disabled"]:
			result.set_icon(name, type_name, _check_icon(not "unchecked" in name, "radio" in name, "disabled" in name))
	for type_name in ["LineEdit", "TextEdit"]:
		result.set_stylebox("normal", type_name, bevel(Color.WHITE, true, 5))
		result.set_stylebox("read_only", type_name, bevel(FACE, true, 5))
		result.set_color("selection_color", type_name, selection)
		result.set_color("font_selected_color", type_name, Color.WHITE)
	for type_name in ["ItemList", "Tree"]:
		result.set_stylebox("panel", type_name, bevel(Color.WHITE, true, 4))
		for state in result.get_stylebox_list(type_name):
			if "selected" in state or state.begins_with("cursor"):
				result.set_stylebox(state, type_name, flat(selection, 3))
			elif state == "hovered":
				result.set_stylebox(state, type_name, flat(FACE, 3))
		result.set_color("font_selected_color", type_name, Color.WHITE)
		result.set_color("font_hovered_selected_color", type_name, Color.WHITE)
		result.set_color("guide_color", type_name, SHADOW)
	result.set_stylebox("panel", "PopupMenu", bevel(Color.WHITE if dos else FACE, false, 4))
	result.set_stylebox("hover", "PopupMenu", flat(selection, 3))
	result.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	result.set_constant("v_separation", "PopupMenu", 6)
	for type_name in ["MenuButton", "FlatButton", "FlatMenuButton"]:
		if type_name != "MenuButton":
			result.set_type_variation(type_name, "Button")
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var active: bool = state in ["hover", "pressed", "hover_pressed"]
			result.set_stylebox(state, type_name, flat(selection if active else FACE, 4))
			result.set_color("font_color" if state == "normal" else "font_" + state + "_color", type_name, Color.WHITE if active else Color.BLACK)
	for type_name in ["TabContainer", "TabBar"]:
		for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
			result.set_stylebox(state, type_name, bevel(FACE, false, 6))
		result.set_stylebox("tab_focus", type_name, focus)
		result.set_color("font_selected_color", type_name, Color.BLACK)
	for type_name in ["HScrollBar", "VScrollBar"]:
		for state in ["scroll", "scroll_focus"]:
			result.set_stylebox(state, type_name, bevel(Color("dddddd"), true, 2))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, type_name, bevel(FACE, state == "grabber_pressed", 7))
	for type_name in ["HSlider", "VSlider"]:
		for state in ["slider", "grabber_area", "grabber_area_highlight"]:
			result.set_stylebox(state, type_name, bevel(FACE, true, 2))
		for name in ["grabber", "grabber_highlight", "grabber_disabled"]:
			result.set_icon(name, type_name, _button_icon(Vector2i(12, 20) if type_name == "HSlider" else Vector2i(20, 12)))
	for direction in ["up", "down"]:
		for state in ["", "_hovered", "_pressed", "_disabled"]:
			result.set_stylebox(direction + "_background" + state, "SpinBox", bevel(FACE, state == "_pressed", 0))
		for state in ["", "_hover", "_pressed", "_disabled"]:
			result.set_color(direction + state + "_icon_modulate", "SpinBox", Color.BLACK)
	result.set_stylebox("background", "ProgressBar", bevel(FACE, true, 2))
	result.set_stylebox("fill", "ProgressBar", flat(selection, 0))
	var separator := bevel(FACE, true, 0)
	separator.content_margin_top = 2
	separator.content_margin_bottom = 0
	for type_name in ["HSeparator", "VSeparator", "PopupMenu"]:
		result.set_stylebox("separator", type_name, separator)
	result.set_stylebox("panel", "TooltipPanel", flat(Color("ffffe1"), 5))
	result.set_color("font_color", "TooltipLabel", Color.BLACK)
	result.set_stylebox("embedded_border", "Window", _window_frame(FACE if dos else NAVY))
	result.set_stylebox("embedded_unfocused_border", "Window", _window_frame(FACE if dos else SHADOW))
	result.set_constant("title_height", "Window", 26)
	result.set_constant("close_h_offset", "Window", 22)
	result.set_constant("close_v_offset", "Window", 24)
	result.set_icon("close", "Window", _button_icon(Vector2i(18, 18), true))
	result.set_icon("close_pressed", "Window", _button_icon(Vector2i(18, 18), true, true))
	for entry in [["error", "800000"], ["warning", "805000"], ["map_canvas", "351800"], ["canvas", "c0c0c0"], ["ink", "000000"], ["paper", "ffffff"], ["chart_accent", "000080"], ["grid", "808080"], ["border", "808080"]]:
		result.set_color(entry[0], "AppPalette", Color(entry[1]))
	for entry in [["HelpLabel", "000000"], ["WarningLabel", "805000"], ["ErrorLabel", "800000"], ["SuccessLabel", "008000"], ["SectionHeading", "000000"]]:
		result.set_type_variation(entry[0], "Label")
		result.set_color("font_color", entry[0], Color(entry[1]))
	result.set_font("font", "SectionHeading", bold)
	for type_name in ["ArtworkButton", "ToolbarArtworkButton", "ToolbarCategoryButton", "PrimaryButton", "SecondaryButton", "NavigationButton"]:
		result.set_type_variation(type_name, "Button")
		if "Artwork" in type_name or type_name == "ToolbarCategoryButton":
			for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
				result.set_color("icon_" + state + "_color", type_name, Color.WHITE)
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				result.set_stylebox(state, type_name, bevel(FACE, state in ["pressed", "hover_pressed"], 3))
	for entry in [["PanelPadding0_0_0_0", 0, 0, 0, 0], ["PanelPadding44_34_44_34", 44, 34, 44, 34], ["PanelPadding5_2_5_2", 5, 2, 5, 2], ["PanelPadding5_3_5_3", 5, 3, 5, 3], ["PanelPadding8_8_8_8", 8, 8, 8, 8]]:
		result.set_type_variation(entry[0], "PanelContainer")
		var box := bevel(FACE, false, 0)
		for side in range(4):
			box.set_content_margin(side, entry[side + 1])
		result.set_stylebox("panel", entry[0], box)
	for type_name in ["FloatingPanel", "MainMenuPanel", "CityToolbarPanel", "CityMenuBarPanel", "CityStatusBarPanel", "InformationPanel", "UtilityPanel"]:
		result.set_type_variation(type_name, "PanelContainer")
		result.set_stylebox("panel", type_name, bevel(FACE, type_name == "InformationPanel", 8 if type_name in ["InformationPanel", "UtilityPanel", "FloatingPanel"] else 3))
	result.set_type_variation("MapLegend", "Panel")
	result.set_stylebox("panel", "MapLegend", bevel(FACE, false, 5))
	result.set_color("font_color", "MapLegend", Color.BLACK)
	result.set_type_variation("DialogMargin", "MarginContainer")
	for side in ["left", "top", "right", "bottom"]:
		result.set_constant("margin_" + side, "DialogMargin", 12)
	for type_name in ["VBoxContainer", "HBoxContainer"]:
		result.set_constant("separation", type_name, 6)
	return result


static func _font(bold: bool) -> Font:
	if _fonts.has(bold):
		return _fonts[bold]
	var path := "res://assets/fonts/classic/ms_sans_serif_bold.ttf" if bold else "res://assets/fonts/classic/ms_sans_serif.ttf"
	var font := load(path).duplicate() as FontFile
	# Keep the authored pixel grid stable when a viewport requests fractional
	# oversampling. The classic canvas repeats these texels without blending.
	font.oversampling = 1.0
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_fonts[bold] = AppLocalization.with_fallback(font, bold)
	return _fonts[bold]


static func _ink_icon(source: Texture2D) -> Texture2D:
	if source is DPITexture:
		var colors := RegEx.create_from_string("#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\\b")
		var svg: String = source.get_source()
		var matches := colors.search_all(svg)
		matches.reverse()
		for found in matches:
			# Keep the negative space of multicolor icons, such as the file grid.
			var ink := "#000000" if Color(found.get_string()).get_luminance() > 0.4 else "#c0c0c0"
			svg = svg.left(found.get_start()) + ink + svg.substr(found.get_end())
		return DPITexture.create_from_string(svg)
	var image := source.get_image()
	if image == null:
		return source
	for y in image.get_height():
		for x in image.get_width():
			image.set_pixel(x, y, Color(0, 0, 0, image.get_pixel(x, y).a))
	return ImageTexture.create_from_image(image)


static func flat(fill: Color, padding: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.set_content_margin_all(padding)
	return result


static func _bevel_image(size: Vector2i, fill: Color, sunken := false) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	var lights := [SHADOW, Color.BLACK] if sunken else [Color.WHITE, Color("dfdfdf")]
	var darks := [Color.WHITE, Color("dfdfdf")] if sunken else [Color.BLACK, SHADOW]
	for edge in range(2):
		for x in range(edge, size.x - edge):
			image.set_pixel(x, edge, lights[edge])
			image.set_pixel(x, size.y - edge - 1, darks[edge])
		for y in range(edge, size.y - edge):
			image.set_pixel(edge, y, lights[edge])
			image.set_pixel(size.x - edge - 1, y, darks[edge])
	return image


static func bevel(fill: Color, sunken: bool, padding: int) -> StyleBoxTexture:
	var result := StyleBoxTexture.new()
	result.texture = ImageTexture.create_from_image(_bevel_image(Vector2i(8, 8), fill, sunken))
	for side in range(4):
		# Include one solid face pixel in each slice to prevent linear sampling
		# from bleeding the border across a stretched panel's center.
		result.set_texture_margin(side, 3)
		result.set_content_margin(side, padding)
	return result


static func _window_frame(title: Color) -> StyleBoxTexture:
	var image := _bevel_image(Vector2i(12, 38), FACE)
	image.fill_rect(Rect2i(3, 3, 6, 23), title)
	var result := bevel(FACE, false, 0)
	result.texture = ImageTexture.create_from_image(image)
	result.texture_margin_top = 29
	result.texture_margin_left = 4
	result.texture_margin_right = 4
	result.expand_margin_top = 29
	result.expand_margin_left = 3
	result.expand_margin_right = 3
	result.expand_margin_bottom = 3
	return result


static func _button_icon(size: Vector2i, close := false, pressed := false) -> Texture2D:
	var image := _bevel_image(size, FACE, pressed)
	if close:
		for i in range(5, 13):
			image.set_pixel(i, i, Color.BLACK)
			image.set_pixel(17 - i, i, Color.BLACK)
	return ImageTexture.create_from_image(image)


static func _check_icon(checked: bool, radio: bool, disabled: bool) -> Texture2D:
	var image := _bevel_image(Vector2i(14, 14), FACE if disabled else Color.WHITE, true)
	var ink := SHADOW if disabled else Color.BLACK
	if radio:
		for y in range(14):
			for x in range(14):
				var distance := Vector2(x - 6.5, y - 6.5).length()
				if distance > 6.5:
					image.set_pixel(x, y, Color.TRANSPARENT)
				elif distance > 5.2 or (checked and distance < 2.5):
					image.set_pixel(x, y, ink)
	elif checked:
		for x in range(3, 11):
			var y := 8 - absi(x - 5)
			image.set_pixel(x, y, ink)
			image.set_pixel(x, y + 1, ink)
	return ImageTexture.create_from_image(image)
