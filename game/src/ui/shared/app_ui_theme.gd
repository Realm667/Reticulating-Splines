class_name AppUiTheme
extends RefCounted

const IDS := ["light", "dark", "classic_windows", "classic_dos"]

static var selected := "dark"
static var translucent_menus := true
static var _current: Theme
static var _files: Theme


static func current() -> Theme:
	if _current == null:
		_current = build(selected)
	return _current


static func file_dialog() -> Theme:
	if _files == null:
		_files = build(selected, true)
	return _files


static func select(value: String, translucent := true) -> void:
	selected = normalize(value)
	translucent_menus = translucent
	# keep resource identities so hidden windows and retained editors update too
	if _current != null:
		_current.set_block_signals(true)
		_current.clear()
		_current.merge_with(build(selected))
		_current.set_block_signals(false)
		_current.emit_changed()
	if _files != null:
		_files.set_block_signals(true)
		_files.clear()
		_files.merge_with(build(selected, true))
		_files.set_block_signals(false)
		_files.emit_changed()


static func bind_canvas(control: ColorRect, role := "canvas") -> void:
	var refresh := func() -> void: control.color = control.get_theme_color(role, "AppPalette")
	control.theme_changed.connect(refresh)
	refresh.call()


static func bind_frosted_panel(control: Control, background_copy: BackBufferCopy = null) -> void:
	var glass_material := control.material
	var refresh := func() -> void:
		control.material = glass_material if uses_translucency() else null
		if background_copy != null:
			background_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if uses_translucency() else BackBufferCopy.COPY_MODE_DISABLED
	control.theme_changed.connect(refresh)
	refresh.call()


static func normalize(value: String) -> String:
	return value if value in IDS else "dark"


static func is_classic(value := "") -> bool:
	return (selected if value.is_empty() else value) in ["classic_windows", "classic_dos"]


static func uses_translucency() -> bool:
	return translucent_menus and not is_classic()


# builds with the selected translucent menu setting held by this class
static func build(value: String, files := false) -> Theme:
	return AppUiThemeDefinitions.build(value, files, translucent_menus)
