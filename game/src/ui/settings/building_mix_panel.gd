class_name BuildingMixPanel
extends VBoxContainer
## Editing is staged; only bundled RS art can supplement original SC2000.
signal applied(options: Dictionary)
var options := BuildingVariants.normalize({})
var body: VBoxContainer
var status: Label
var available := true


func _ready() -> void:
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(body)
	show_values(options)


func show_values(value: Dictionary, notices := PackedStringArray(), can_mix := true) -> void:
	options = BuildingVariants.normalize(value)
	available = can_mix
	_rebuild()
	status.text = "\n".join(notices)
	if not available:
		status.text = tr("Select imported SC2000 graphics in Data to mix them with Reticulating Splines.")


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _weight(text: String, key: String) -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	row.add_child(_label(text))
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 100
	spin.step = 5
	spin.value = options[key]
	spin.editable = available
	spin.custom_minimum_size.x = 90
	spin.value_changed.connect(func(value: float) -> void: options[key] = int(value))
	row.add_child(spin)


func _rebuild() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var enabled := CheckBox.new()
	enabled.text = "Mix RS and SC2000 buildings"
	enabled.button_pressed = options.enabled
	enabled.disabled = not available and not options.enabled
	enabled.toggled.connect(func(value: bool) -> void: options.enabled = value)
	body.add_child(enabled)
	body.add_child(_label("Mix only Reticulating Splines with the original SC2000 buildings. Other tile sets and HD overrides are not used while mixing."))
	body.add_child(_label("Weights are relative for compatible buildings in the selected categories. Missing alternatives keep the original. Both weights at zero also keep the original."))
	_weight("SC2000 weight", "original_weight")
	_weight("Reticulating Splines weight", "rs_weight")
	var categories := GridContainer.new()
	categories.columns = 2
	body.add_child(categories)
	for index in BuildingVariants.CATEGORIES.size():
		var check := CheckBox.new()
		check.disabled = not available
		check.text = BuildingVariants.CATEGORIES[index]
		check.button_pressed = options.categories.has(index)
		check.toggled.connect(func(value: bool) -> void:
			if value:
				options.categories.append(index)
			else:
				options.categories.erase(index))
		categories.add_child(check)
	var shuffle := Button.new()
	shuffle.disabled = not available
	shuffle.text = "Shuffle again"
	shuffle.pressed.connect(func() -> void:
		options.seed = (int(options.seed)+1) % 2147483647
		status.text = tr("New building choices will be used after Apply."))
	body.add_child(shuffle)
	status = _label("")
	body.add_child(status)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(func() -> void: applied.emit(BuildingVariants.normalize(options)))
	body.add_child(apply)
