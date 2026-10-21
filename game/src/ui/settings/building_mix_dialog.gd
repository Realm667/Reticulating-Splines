class_name BuildingMixDialog
extends ConfirmationDialog
## Editing is staged; Apply rebuilds the artwork banks once.
signal applied(options: Dictionary)
var options := BuildingVariants.normalize({})
var body: VBoxContainer
var pack_rows: VBoxContainer
var status: Label
var picker: FileDialog


func _ready() -> void:
	title = "Building variants"
	get_ok_button().text = "Apply"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500,380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	picker = FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	picker.title = "Add tile sets…"
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.mif ; " + tr("SCURK tile set")])
	add_child(picker)
	picker.files_selected.connect(add_paths)
	confirmed.connect(func() -> void: applied.emit(BuildingVariants.normalize(options)))


func open(value: Dictionary, notices := PackedStringArray()) -> void:
	options = BuildingVariants.normalize(value)
	picker.filters = PackedStringArray(["*.mif ; " + tr("SCURK tile set")])
	_rebuild()
	status.text = "\n".join(notices)
	popup_centered_clamped(Vector2i(760,650),0.85)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _weight(row: HBoxContainer, value: int, changed: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 100
	spin.step = 5
	spin.value = value
	spin.custom_minimum_size.x = 90
	spin.value_changed.connect(changed)
	row.add_child(spin)
	return spin


func _rebuild() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var enabled := CheckBox.new()
	enabled.text = "Mix building tile sets"
	enabled.button_pressed = options.enabled
	enabled.toggled.connect(func(value: bool) -> void: options.enabled = value)
	body.add_child(enabled)
	body.add_child(_label("Choose local SCURK MIF files. Mixing uses the base graphics instead of replacement tile sets. Changes affect appearance only."))
	body.add_child(_label("Weights are relative for each building with compatible alternatives. A missing or incomplete family keeps the original. Additional artwork needs its own matching light masks."))
	var original := HBoxContainer.new()
	body.add_child(original)
	original.add_child(_label("Original weight"))
	_weight(original,options.original_weight,func(value: float) -> void: options.original_weight = int(value))
	pack_rows = VBoxContainer.new()
	body.add_child(pack_rows)
	for pack: Dictionary in options.packs:
		var row := HBoxContainer.new()
		pack_rows.add_child(row)
		var enabled_pack := CheckBox.new()
		enabled_pack.text = str(pack.path).get_file()
		enabled_pack.tooltip_text = pack.path
		enabled_pack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		enabled_pack.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		enabled_pack.button_pressed = pack.enabled
		enabled_pack.toggled.connect(func(value: bool) -> void: pack.enabled = value)
		row.add_child(enabled_pack)
		_weight(row,pack.weight,func(value: float) -> void: pack.weight = int(value))
		var remove := Button.new()
		remove.text = "Remove"
		row.add_child(remove)
		remove.pressed.connect(func() -> void:
			options.packs.erase(pack)
			_rebuild.call_deferred())
	var add := Button.new()
	add.text = "Add tile sets…"
	add.disabled = options.packs.size() >= BuildingVariants.MAX_PACKS
	add.pressed.connect(func() -> void: picker.popup_centered_clamped(Vector2i(800,600),0.8))
	body.add_child(add)
	body.add_child(_label("Up to 8 local sets. Equal weights give equal chances; actual counts vary."))
	var categories := GridContainer.new()
	categories.columns = 2
	body.add_child(categories)
	for index in BuildingVariants.CATEGORIES.size():
		var check := CheckBox.new()
		check.text = BuildingVariants.CATEGORIES[index]
		check.button_pressed = options.categories.has(index)
		check.toggled.connect(func(value: bool) -> void:
			if value:
				options.categories.append(index)
			else:
				options.categories.erase(index))
		categories.add_child(check)
	var shuffle := Button.new()
	shuffle.text = "Shuffle again"
	shuffle.pressed.connect(func() -> void:
		options.seed = (int(options.seed)+1) % 2147483647
		status.text = tr("New building choices will be used after Apply."))
	body.add_child(shuffle)
	status = _label("")
	body.add_child(status)


func add_paths(paths: PackedStringArray) -> void:
	for path in paths:
		if path.get_extension().to_lower() != "mif" or not FileAccess.file_exists(path):
			continue
		if options.packs.size() < BuildingVariants.MAX_PACKS and not options.packs.any(func(p: Dictionary) -> bool: return p.path == path):
			options.packs.append({"path": path,"enabled": true,"weight": 50})
	_rebuild()
