class_name BuildingMixPanel
extends VBoxContainer
## Editing is staged; only bundled RS art can supplement original SC2000.
signal applied(options: Dictionary)
var options := BuildingVariants.normalize({})
var body: VBoxContainer
var status: Label
var available := true
var mix_slider: HSlider
var mix_ratio: Label


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


func _mix_weight() -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	row.add_child(_label("SC2000"))
	mix_ratio = _label("")
	mix_ratio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(mix_ratio)
	var right := _label("RS")
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)
	mix_slider = HSlider.new()
	mix_slider.min_value = 0
	mix_slider.max_value = 100
	mix_slider.step = 1
	mix_slider.tick_count = 3
	mix_slider.ticks_on_borders = true
	mix_slider.editable = available
	mix_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var total: int = options.original_weight + options.rs_weight
	# Preserve the ratio of old independent weights, including all-original 0/0.
	mix_slider.value = roundf(100.0 * options.rs_weight / total) if total > 0 else 0.0
	mix_slider.value_changed.connect(_set_mix_weight)
	mix_ratio.text = "%d%% / %d%%" % [100 - int(mix_slider.value), int(mix_slider.value)]
	body.add_child(mix_slider)


func _set_mix_weight(value: float) -> void:
	options.rs_weight = int(value)
	options.original_weight = 100 - int(value)
	mix_ratio.text = "%d%% / %d%%" % [options.original_weight, options.rs_weight]


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
	body.add_child(_label("Choose the mix for the selected categories. The center gives equal shares of SC2000 and RS."))
	_mix_weight()
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
	status = _label("")
	body.add_child(status)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(func() -> void:
		if available and options.enabled:
			options.seed = (int(options.seed) + 1) % 2147483647
		applied.emit(BuildingVariants.normalize(options)))
	body.add_child(apply)
