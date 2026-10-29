class_name ActivityReporter
extends HTTPRequest
## One short-lived opt-in presence lease. Never opens a listener or maps a port.

var room := Crypto.new().generate_random_bytes(16).hex_encode()
var secret := Crypto.new().generate_random_bytes(32).hex_encode()
var payload: Dictionary = {}
var pending := false
var closing := false
var deleting := false
var next_update := 0
var last_code := 0
var last_result := -1
var start_error := OK


func _ready() -> void:
	timeout = 8.0
	body_size_limit = 8192
	max_redirects = 0
	request_completed.connect(_completed)


func update(value: Dictionary, now := Time.get_ticks_msec()) -> void:
	payload = value
	if not pending and not closing and now >= next_update:
		next_update = now + 60000
		_send(false)


func finish() -> void:
	closing = true
	# Wait for an in-flight PUT before DELETE, preventing a late ghost listing.
	if not pending:
		_send(true)


func _send(remove: bool) -> void:
	deleting = remove
	pending = true
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + secret])
	var error := request(MultiplayerOnline.base_url() + MultiplayerOnline.API + "/singleplayer/" + room,
		headers, HTTPClient.METHOD_DELETE if remove else HTTPClient.METHOD_PUT,
		"" if remove else JSON.stringify(payload))
	start_error = error
	if error != OK:
		_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _completed(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	last_code = _code
	last_result = _result
	pending = false
	if deleting:
		queue_free()
	elif closing:
		_send(true)
	# Failures retry at the normal minute interval; no gameplay/modal feedback.
