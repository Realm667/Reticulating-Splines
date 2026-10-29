class_name SingleplayerActivity
extends Node
## Local preference controls all single-player requests, including at startup.

var app: CityApplication
var reporter: ActivityReporter
var document_ref: WeakRef
var next_check := 0
var stopping := false


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() < next_check:
		return
	next_check = Time.get_ticks_msec() + 1000
	sync()


func eligible() -> bool:
	return not stopping and app != null and app.preferences.share_singleplayer_activity \
		and app.document_state.city != null and app.document_state.current_document != null \
		and not app.coop.active() and not app.tool_state.landscape_editor \
		and not app.city_files.load_in_progress and app.new_city_state.session.preview_document == null \
		and app.main_menu != null and not app.main_menu.visible \
		and (app.scurk_editor == null or not app.scurk_editor.visible) \
		and (app.scurk_place_print == null or not app.scurk_place_print.visible)


func sync() -> void:
	var document := app.document_state.current_document if eligible() else null
	var previous: Variant = document_ref.get_ref() if document_ref != null else null
	if document == null or document != previous:
		if is_instance_valid(reporter):
			reporter.finish()
			reporter = null
		document_ref = weakref(document) if document != null else null
	if document == null:
		return
	if reporter == null:
		reporter = ActivityReporter.new()
		add_child(reporter)
	var identity := CityActivityIdentity.ensure(document)
	var paused := app.simulation_state.speed_controller == null \
		or app.simulation_state.speed_controller.speed == GameSpeedController.Speed.PAUSED
	reporter.update({"version": 2, "activity": {"city": public_name(app.document_state.city.city_name()),
		"phase": "paused" if paused else "running"},
		"cities": [{"id": identity, "population": app.document_state.city.population()}]})


static func public_name(value: String) -> String:
	var result := ""
	for character in value:
		if character.unicode_at(0) >= 32 and character.unicode_at(0) != 127:
			result += character
	return result.left(64)


func shutdown() -> void:
	stopping = true
	sync()
	# Give normal quit a bounded chance to unlist; expiry handles offline/crashes.
	var until := Time.get_ticks_msec() + 1500
	while get_child_count() > 0 and Time.get_ticks_msec() < until:
		await get_tree().process_frame
