class_name CloudWindow
extends QolDialog
## Standalone shell; the same Cloud panel is embedded in the load dialog.

signal downloaded(path: String)
signal opt_in_changed(path: String, enabled: bool)

var content: CloudPanel


func _init() -> void:
	super()
	title = "Account & Cloud"
	wrap_controls = false
	min_size = Vector2i(300, 260)
	size = Vector2i(760, 620)
	content = CloudPanel.new()
	column.add_child(content)
	content.close_requested.connect(hide)
	content.downloaded.connect(func(path: String) -> void: downloaded.emit(path))
	content.opt_in_changed.connect(func(path: String, enabled: bool) -> void: opt_in_changed.emit(path, enabled))
	visibility_changed.connect(func() -> void:
		if not visible:
			content.clear_secrets())


func _ready() -> void:
	get_parent().get_viewport().size_changed.connect(func() -> void:
		if visible:
			content._fit(self, Vector2i(760, 620)))


func bind(service: Node) -> void:
	content.bind(service)


func set_current_path(path: String) -> void:
	content.set_current_path(path)


func open() -> void:
	theme = AppUiTheme.current()
	content.open()
	content._fit(self, Vector2i(760, 620))


func confirm_exit(callback: Callable) -> void:
	content.confirm_exit(callback)


static func error_message(error: String) -> String:
	return CloudPanel.error_message(error)
