class_name AppUiMacTheme
extends RefCounted
## System 7-inspired monochrome chrome, using the bundled free pixel font.


static func build(files := false) -> Theme:
	var result := AppUiClassicTheme.build("classic_dos", false, files)
	var paper := Color("eeeeee")
	result.set_color("title_background", "AppPalette", Color.WHITE)
	result.set_color("canvas", "AppPalette", paper)
	result.set_color("map_canvas", "AppPalette", Color("202020"))
	result.set_color("border", "AppPalette", Color.BLACK)
	for type_name in ["Button", "OptionButton", "PrimaryButton", "SecondaryButton", "NavigationButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var pressed: bool = state in ["pressed", "hover_pressed"]
			var box := _box(Color.BLACK if pressed else Color.WHITE, 6, 5)
			result.set_stylebox(state, type_name, box)
			result.set_stylebox(state + "_mirrored", type_name, box)
		result.set_color("font_pressed_color", type_name, Color.WHITE)
		result.set_color("font_hover_pressed_color", type_name, Color.WHITE)
		result.set_color("icon_pressed_color", type_name, Color.WHITE)
		result.set_color("icon_hover_pressed_color", type_name, Color.WHITE)
	for type_name in ["Panel", "PanelContainer", "AcceptDialog", "PopupPanel", "PopupMenu", "TabContainer"]:
		result.set_stylebox("panel", type_name, _box(Color.WHITE if type_name == "PopupMenu" else paper, 8))
	for type_name in ["FloatingPanel", "MainMenuPanel", "CityToolbarPanel", "CityMenuBarPanel", "CityStatusBarPanel", "InformationPanel", "UtilityPanel"]:
		result.set_stylebox("panel", type_name, _box(paper, 3))
	for type_name in ["LineEdit", "TextEdit"]:
		result.set_stylebox("normal", type_name, _box(Color.WHITE, 5))
	for type_name in ["HScrollBar", "VScrollBar"]:
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, type_name, _box(Color.WHITE, 7))
	result.set_stylebox("embedded_border", "Window", _frame(true))
	result.set_stylebox("embedded_unfocused_border", "Window", _frame(false))
	result.set_color("title_unfocused_color", "Window", Color("666666"))
	var image := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.fill_rect(Rect2i(3, 3, 12, 12), Color.BLACK)
	image.fill_rect(Rect2i(4, 4, 10, 10), Color.WHITE)
	result.set_icon("close", "Window", ImageTexture.create_from_image(image))
	image.fill_rect(Rect2i(5, 5, 8, 8), Color.BLACK)
	result.set_icon("close_pressed", "Window", ImageTexture.create_from_image(image))
	return result


static func _box(fill: Color, padding: int, radius := 0) -> StyleBoxFlat:
	var box := AppUiClassicTheme.flat(fill, padding)
	box.border_color = Color.BLACK
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.anti_aliasing = false
	return box


static func _frame(active: bool) -> StyleBoxTexture:
	var image := Image.create(256, 38, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.fill_rect(Rect2i(1, 1, 254, 36), Color("eeeeee"))
	image.fill_rect(Rect2i(2, 2, 252, 25), Color.WHITE)
	if active:
		for y in range(5, 24, 3):
			image.fill_rect(Rect2i(7, y, 60, 1), Color("555555"))
			image.fill_rect(Rect2i(189, y, 60, 1), Color("555555"))
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(image)
	box.texture_margin_left = 70
	box.texture_margin_right = 70
	box.texture_margin_top = 29
	box.texture_margin_bottom = 3
	box.expand_margin_top = 29
	box.expand_margin_left = 3
	box.expand_margin_right = 3
	box.expand_margin_bottom = 3
	return box
