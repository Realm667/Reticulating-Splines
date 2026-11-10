class_name QuarterTerrainPanel
extends VBoxContainer
## City capability controls live beside Models; their data is saved in XQTR.

# Keep the settings scene loadable before the main application scene.
var app: Node
var enable_button: Button
var step: OptionButton
var grade: OptionButton
var help: Label
var filling := false


func _ready() -> void:
	add_child(HSeparator.new())
	var heading:=Label.new()
	heading.text="Quarter-height terrain"
	heading.theme_type_variation=&"SectionHeading"
	add_child(heading)
	help=Label.new()
	help.text="Quarter-height terrain is saved with the city. Models are required to display it."
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	enable_button=Button.new()
	enable_button.text="Enable quarter-height terrain"
	enable_button.disabled=true
	enable_button.pressed.connect(_enable)
	add_child(enable_button)
	step=_choice("Edit height",["¼ level","½ level","1 level","2 levels"])
	grade=_choice("Maximum slope",["Gentle","Normal","Steep","Vertical cliffs"])
	step.item_selected.connect(_selected)
	grade.item_selected.connect(_selected)
	var rules:=Label.new()
	rules.text="Roads, railways and power lines require gentle or normal slopes. Buildings and zones require level ground. Terrain costs follow the height moved."
	rules.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(rules)
	sync(null)


func _choice(title: String,items: Array) -> OptionButton:
	var row:=HBoxContainer.new()
	var label:=Label.new()
	label.text=title
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var selector:=OptionButton.new()
	for item: String in items:
		selector.add_item(item)
	selector.disabled=true
	row.add_child(selector)
	add_child(row)
	return selector


func sync(application: Node) -> void:
	app=application
	if not is_node_ready():
		return
	filling=true
	var city: CityState=app.document_state.city if app!=null else null
	var active:=city!=null and QuarterTerrain.enabled(city.document)
	var can_edit: bool=city!=null and not app.coop.active()
	enable_button.visible=not active
	enable_button.disabled=not can_edit or not ExpandedRules.enabled(city.document) or not app.preferences.visual_enhancements.models_enabled
	enable_button.tooltip_text=tr("Quarter-height terrain requires Expanded rules.") if city==null or not ExpandedRules.enabled(city.document) else tr("Quarter-height terrain is saved with the city. Models are required to display it.")
	step.disabled=not active or not can_edit
	grade.disabled=not active or not can_edit
	if app!=null:
		var check:=app.main_overlays.settings_dialog.visual_tab.controls.models_enabled as CheckBox
		check.disabled=active
	if active:
		var bytes:=city.document.find_chunk("XQTR").decoded_payload
		step.select(QuarterTerrain.STEPS.find(bytes[6]))
		grade.select(QuarterTerrain.GRADES.find(bytes[7]))
		var check:=app.main_overlays.settings_dialog.visual_tab.controls.models_enabled as CheckBox
		check.set_pressed_no_signal(true)
	filling=false


func _enable() -> void:
	if app==null or app.document_state.city==null:
		return
	var error:=QuarterTerrain.enable(app.document_state.city)
	if not error.is_empty():
		app.interface.show_error(error)
		return
	app.preferences.visual_enhancements.models_enabled=true
	app.visual_environment.configure()
	app.static_render.invalidate_rendered_city()
	app.map_render.refresh_map()
	sync(app)


func _selected(_index: int) -> void:
	if not filling and app!=null and app.document_state.city!=null:
		QuarterTerrain.configure(app.document_state.city,QuarterTerrain.STEPS[step.selected],QuarterTerrain.GRADES[grade.selected])
