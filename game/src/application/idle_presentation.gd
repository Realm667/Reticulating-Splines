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
	# Paused does not mean idle while graphics are being prepared. A 15 FPS
	# cap also makes the cooperative loader mistake deliberate waits for load.
	eligible = eligible and not app.visual_preparation.busy
	eligible = eligible and not (app.photo_mode != null and app.photo_mode.capturing)
	# A paused city can still have an active dialog. Keep its presentation at
	# the user's normal cadence; only the quiet map should enter idle saving.
	eligible = eligible and not _has_active_dialog()
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


func _has_active_dialog() -> bool:
	if app.city_dialogs != null and (app.city_dialogs.blocks_simulation() or app.city_dialogs.has_visible_window()):
		return true
	return app.main_overlays != null and (
		app.main_overlays.blocks_simulation()
		or CityDialogRegistry.any_window_visible(app.main_overlays.modeless_windows)
	)


func restore() -> void:
	if saved_limit >= 0:
		if Engine.max_fps == applied_limit:
			Engine.max_fps = saved_limit
		saved_limit = -1


func _exit_tree() -> void:
	restore()
