class_name CityWorkspace
extends Control

var toolbar_art: Image
var menu_bar: CityMenuBar
var toolbar: CityToolbar
var map_view: CityMapControl
var status_bar: CityStatusBar
var _palette_scroll: ScrollContainer
var _rci_parent: Node
var _rci_index := 0
var _classic_layout := false
var _bar_scrolls: Array[ScrollContainer] = []


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
	theme_changed.connect(_sync_classic_layout.call_deferred)
	resized.connect(_fit_palette.call_deferred)
	toolbar.minimum_size_changed.connect(_fit_palette.call_deferred)
	$Page/Content/MapSpace.item_rect_changed.connect(_sync_camera_rect)
	$Page.visibility_changed.connect(_sync_camera_rect)
	_sync_camera_rect.call_deferred()
	_sync_classic_layout.call_deferred()
	menu_bar.resized.connect(_fit_palette.call_deferred)
	status_bar.resized.connect(_fit_palette.call_deferred)


func set_editor_controls_visible(value: bool) -> void:
	$Page.visible = value
	_palette_scroll.visible = value and _classic_layout


func _sync_camera_rect() -> void:
	var map_space: Control = $Page/Content/MapSpace
	map_view.camera_view_rect = (
		Rect2(map_space.global_position - map_view.global_position, map_space.size)
		if $Page.visible else Rect2()
	)


func _sync_classic_layout() -> void:
	if not is_node_ready() or _classic_layout == AppUiTheme.is_classic():
		return
	_classic_layout = AppUiTheme.is_classic()
	# Exact 2x classic pixels can make the fixed-width metric bars wider than
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
		bar.reparent(scroll if _classic_layout else $Page)
		scroll.visible = _classic_layout
		$Page.move_child(scroll if _classic_layout else bar, 0 if index == 0 else $Page.get_child_count() - 1)
	$Page/Content/MapSpace.custom_minimum_size = Vector2.ZERO if _classic_layout else Vector2(560, 480)
	toolbar.reparent(_palette_scroll if _classic_layout else $Page/Content)
	if not _classic_layout:
		$Page/Content.move_child(toolbar, 0)
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
