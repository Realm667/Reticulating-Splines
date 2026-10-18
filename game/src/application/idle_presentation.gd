class_name IdlePresentation
extends Node
## Only throttle an already paused singleplayer view. Never suspend networking.

var app: CityApplication
var quiet_seconds := 0.0
var saved_limit := -1
var applied_limit := -1


func _init(application: CityApplication) -> void:
	app = application


func _input(_event: InputEvent) -> void:
	quiet_seconds = 0.0
	restore()


func _process(delta: float) -> void:
	quiet_seconds += delta
	var controller := app.simulation_state.speed_controller
	var eligible: bool = app.preferences.visual_enhancements.get("idle_saving_enabled", true) and not app.coop.active()
	eligible = eligible and controller != null and controller.speed == GameSpeedController.Speed.PAUSED
	eligible = eligible and app.preferences.visual_enhancements.pause_freezes and quiet_seconds >= 2.0
	eligible = eligible and not (app.photo_mode != null and app.photo_mode.capturing)
	if not eligible:
		restore()
		return
	if saved_limit >= 0 and Engine.max_fps != applied_limit:
		# A settings change supersedes our saved value.
		saved_limit = -1
	if saved_limit < 0:
		saved_limit = Engine.max_fps
		applied_limit = mini(saved_limit, 15) if saved_limit > 0 else 15
		Engine.max_fps = applied_limit


func restore() -> void:
	if saved_limit >= 0:
		if Engine.max_fps == applied_limit:
			Engine.max_fps = saved_limit
		saved_limit = -1


func _exit_tree() -> void:
	restore()
