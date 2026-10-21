class_name ApplicationUpdates
extends RefCounted
## Runs the optional check for a newer published release. The automatic check
## shows only a new release that the player did not skip. A check that the
## player requests shows every result.

signal running_changed(running: bool)
signal status_changed(checked_at: int, error: String)

const SettingsStore = preload("res://src/ui/settings/app_settings_store.gd")

var preferences: AppPreferences
var host: Node
var dialog: UpdateCheckDialog
var request: HTTPRequest
var current_version := ReleaseUpdateCheck.current_version()
var running := false
var show_all_outcomes := false
var release_page := 1
var releases: Array = []
const MAX_RELEASE_PAGES := 10


func _init(app_preferences: AppPreferences) -> void:
	preferences = app_preferences


func bind_ui(request_host: Node, update_dialog: UpdateCheckDialog) -> void:
	host = request_host
	dialog = update_dialog
	dialog.download_requested.connect(_download_release)
	dialog.skip_requested.connect(_skip_release)


# check at startup, not more than one time each day
func check_on_startup(now := int(Time.get_unix_time_from_system())) -> void:
	if not preferences.check_for_updates or not ReleaseUpdateCheck.is_due(preferences.update_last_check, now):
		return

	preferences.update_last_check = now
	_save_update_state()
	_start(false)


func check_now() -> void:
	_start(true)


func _start(manual: bool) -> void:
	# a manual request during an automatic check shows that check's result
	show_all_outcomes = show_all_outcomes or manual

	if running:
		return

	release_page = 1
	releases.clear()
	var error := _send_request()

	if error != OK:
		finish(ReleaseUpdateCheck.failed("Cannot start the update check (error %d)." % error))

		return

	running = true
	running_changed.emit(true)


func _send_request() -> Error:
	if request == null:
		request = HTTPRequest.new()
		request.name = "UpdateCheckRequest"
		request.timeout = ReleaseUpdateCheck.TIMEOUT_SECONDS
		request.body_size_limit = ReleaseUpdateCheck.BODY_SIZE_LIMIT
		request.request_completed.connect(_on_request_completed)
		host.add_child(request)

	var url := ReleaseUpdateCheck.LATEST_RELEASE_API + "&page=%d" % release_page
	return request.request(url, PackedStringArray(ReleaseUpdateCheck.REQUEST_HEADERS))


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var now := int(Time.get_unix_time_from_system())
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		finish(ReleaseUpdateCheck.read_response(result, response_code, headers, body, current_version, now), now)
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Array:
		finish(ReleaseUpdateCheck.failed("GitHub returned release information that Reticulating Splines cannot read."), now)
		return
	releases.append_array(json.data)
	var link := ReleaseUpdateCheck.header_value(headers, "link")
	if link.contains('; rel="next"'):
		# Construct our own next URL; never follow a URL from response headers.
		# Fail explicitly on a truncated list instead of claiming it is up to date.
		if release_page >= MAX_RELEASE_PAGES:
			finish(ReleaseUpdateCheck.failed("GitHub returned release information that Reticulating Splines cannot read."), now)
			return
		release_page += 1
		var error := _send_request()
		if error != OK:
			finish(ReleaseUpdateCheck.failed("Cannot start the update check (error %d)." % error), now)
		return
	finish(ReleaseUpdateCheck.select_release(releases, current_version), now)


func finish(outcome: ReleaseUpdateCheck.Outcome, now := int(Time.get_unix_time_from_system())) -> void:
	var manual := show_all_outcomes
	show_all_outcomes = false
	releases.clear()

	if running:
		running = false
		running_changed.emit(false)

	# keep the last result for settings. only a manual check shows a failure
	preferences.update_checked_at = now
	preferences.update_error = outcome.message if outcome.status == ReleaseUpdateCheck.Status.FAILED else ""
	_save_update_state()
	status_changed.emit(preferences.update_checked_at, preferences.update_error)

	match outcome.status:
		ReleaseUpdateCheck.Status.UPDATE_AVAILABLE:
			if manual or outcome.version != preferences.update_skipped_version:
				dialog.show_update(outcome.version, current_version, outcome.url)
		ReleaseUpdateCheck.Status.UP_TO_DATE:
			if manual:
				dialog.show_latest(current_version)
		_:
			if manual:
				dialog.show_failure(outcome.message)


func _download_release(version: String, url: String) -> void:
	_open_url(url)
	_skip_release(version)


func _open_url(url: String) -> void:
	OS.shell_open(url)


# do not show this release again. a newer release has a different version
func _skip_release(version: String) -> void:
	preferences.update_skipped_version = version
	_save_update_state()


func _save_update_state() -> void:
	SettingsStore.save_update_state(preferences.update_last_check, preferences.update_skipped_version,
		preferences.update_checked_at, preferences.update_error, preferences.settings_path)
