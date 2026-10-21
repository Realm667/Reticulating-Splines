class_name CityWorkspace
extends Control

var toolbar_art: Image
var menu_bar: CityMenuBar
var toolbar: CityToolbar
var map_view: CityMapControl
var status_bar: CityStatusBar
var _palette_scroll: ScrollContainer
var _dock_scroll: ScrollContainer
var _rci_parent: Node
var _rci_index := 0
var _classic_layout := false
var _bar_scrolls: Array[ScrollContainer] = []
var dos_hscroll: HScrollBar
var dos_vscroll: VScrollBar
var syncing_scrolls := false


func _enter_tree() -> void:
	# parent enters first, so imported icons are available when the toolbar builds
	toolbar = %Toolbar
	toolbar.toolbar_art = toolbar_art


func _ready() -> void:
	AppUiTheme.bind_canvas($Background, "map_canvas")
	menu_bar = %MenuBar
	toolbar = %Toolbar
	map_view = %MapView
	status_bar = %StatusBar
	_rci_parent = status_bar.rci_graph.get_parent()
	_rci_index = status_bar.rci_graph.get_index()
	_palette_scroll = ScrollContainer.new()
	_palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_palette_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_palette_scroll.visible = false
	add_child(_palette_scroll)
	_dock_scroll = ScrollContainer.new()
	_dock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dock_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	$Page/Content.add_child(_dock_scroll)
	$Page/Content.move_child(_dock_scroll, 0)
	theme_changed.connect(_sync_classic_layout.call_deferred)
	resized.connect(_fit_palette.call_deferred)
	toolbar.minimum_size_changed.connect(_fit_palette.call_deferred)
	$Page/Content/MapSpace.item_rect_changed.connect(_sync_camera_rect)
	$Page.visibility_changed.connect(_sync_camera_rect)
	_sync_camera_rect.call_deferred()
	_sync_classic_layout.call_deferred()
	menu_bar.resized.connect(_fit_palette.call_deferred)
	status_bar.resized.connect(_fit_palette.call_deferred)
	_build_dos_scrolls()


func set_editor_controls_visible(value: bool) -> void:
	$Page.visible = value
	_palette_scroll.visible = value and _classic_layout
	_sync_dos_scrolls()


func _sync_camera_rect() -> void:
	var map_space: Control = $Page/Content/MapSpace
	map_view.camera_view_rect = (
		Rect2(map_space.global_position - map_view.global_position, map_space.size)
		if $Page.visible else Rect2()
	)


func _sync_classic_layout() -> void:
	if not is_node_ready() or (not _bar_scrolls.is_empty() and _classic_layout == AppUiTheme.is_classic()):
		return
	_classic_layout = AppUiTheme.is_classic()
	# Exact 2x pixels can make the fixed-width metric bars wider than
	# the window. Scroll those bars rather than expanding/centering the whole
	# workspace outside the viewport (which made File and map edges disappear).
	if _bar_scrolls.is_empty():
		for index in 2:
			var scroll := ScrollContainer.new()
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.visible = false
			$Page.add_child(scroll)
			_bar_scrolls.append(scroll)
	for index in 2:
		var bar: Control = menu_bar if index == 0 else status_bar
		var scroll := _bar_scrolls[index]
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.reparent(scroll)
		scroll.visible = true
		$Page.move_child(scroll, 0 if index == 0 else $Page.get_child_count() - 1)
	$Page/Content/MapSpace.custom_minimum_size = Vector2.ZERO
	toolbar.reparent(_palette_scroll if _classic_layout else _dock_scroll)
	_dock_scroll.visible = not _classic_layout
	if not _classic_layout:
		status_bar.rci_graph.reparent(_rci_parent)
		_rci_parent.move_child(status_bar.rci_graph, _rci_index)
	else:
		status_bar.rci_graph.reparent(toolbar.classic_footer)
		toolbar.classic_footer.move_child(status_bar.rci_graph, 0)
	_palette_scroll.visible = _classic_layout and $Page.visible
	_fit_palette.call_deferred()
	_sync_camera_rect.call_deferred()


func _fit_palette() -> void:
	if not _classic_layout:
		return
	var top := _bar_scrolls[0].global_position.y - global_position.y + _bar_scrolls[0].size.y + 12
	var available := maxf(48, _bar_scrolls[1].global_position.y - global_position.y - top - 12)
	var minimum := toolbar.get_combined_minimum_size()
	_palette_scroll.position = Vector2(12, top)
	_palette_scroll.size = Vector2(minimum.x + (16 if minimum.y > available else 0), minf(minimum.y, available))


func _build_dos_scrolls() -> void:
	dos_hscroll = HScrollBar.new()
	dos_vscroll = VScrollBar.new()
	dos_hscroll.custom_step = 32.0
	dos_vscroll.custom_step = 32.0
	add_child(dos_hscroll)
	add_child(dos_vscroll)
	dos_hscroll.value_changed.connect(_scroll_dos.bind(0))
	dos_vscroll.value_changed.connect(_scroll_dos.bind(1))
	map_view.viewport_changed.connect(_sync_dos_scrolls)
	theme_changed.connect(_sync_dos_scrolls.call_deferred)
	$Page/Content/MapSpace.item_rect_changed.connect(_sync_dos_scrolls)
	_sync_dos_scrolls()


func _scroll_dos(value: float, axis: int) -> void:
	if not syncing_scrolls:
		map_view.camera.set_scroll_value(axis, value)


func _sync_dos_scrolls() -> void:
	if dos_hscroll == null or syncing_scrolls:
		return
	var active: bool = AppUiTheme.selected == "classic_dos" and $Page.visible
	dos_hscroll.visible = active
	dos_vscroll.visible = active
	if not active:
		return
	syncing_scrolls = true
	var area: Rect2 = $Page/Content/MapSpace.get_global_rect()
	area.position -= global_position
	dos_hscroll.position = Vector2(area.position.x, area.end.y - 16)
	dos_hscroll.size = Vector2(maxf(16, area.size.x - 16), 16)
	dos_vscroll.position = Vector2(area.end.x - 16, area.position.y)
	dos_vscroll.size = Vector2(16, maxf(16, area.size.y - 16))
	var state := map_view.camera.scroll_state()
	for axis in 2:
		var bar: ScrollBar = dos_hscroll if axis == 0 else dos_vscroll
		bar.max_value = state.content[axis] if state != null else 1.0
		bar.page = state.page[axis] if state != null else 1.0
		bar.set_value_no_signal(state.value[axis] if state != null else 0.0)
	syncing_scrolls = false
