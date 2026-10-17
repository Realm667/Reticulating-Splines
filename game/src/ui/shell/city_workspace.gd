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
	var top := menu_bar.position.y + menu_bar.size.y + 12
	var available := maxf(48, status_bar.position.y - top - 12)
	var minimum := toolbar.get_combined_minimum_size()
	_palette_scroll.position = Vector2(12, top)
	_palette_scroll.size = Vector2(minimum.x + (16 if minimum.y > available else 0), minf(minimum.y, available))
