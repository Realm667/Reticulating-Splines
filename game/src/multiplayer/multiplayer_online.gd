class_name MultiplayerOnline
extends Node
## Online discovery is session-local and never written into city saves.

const DEFAULT_URL := "https://rs.realm667.com"
const API := "/api/multiplayer/v1"
var session: CoopSession
var wire := WebSocketPeer.new()
var room := ""
var secret := ""
var registered := false
var sent := false
var closing := false
var next_update := 0
var started := 0
var signature := ""
var failed_reported := false


static func base_url() -> String:
	var configured := OS.get_environment("RS_MULTIPLAYER_URL").trim_suffix("/")
	if configured.begins_with("https://") or configured.begins_with("http://127.0.0.1:") or configured.begins_with("http://localhost:"):
		return configured
	return DEFAULT_URL


static func websocket_url(path: String) -> String:
	return base_url().replace("https://", "wss://").replace("http://", "ws://") + API + path


func start(owner: CoopSession) -> void:
	session = owner
	started = Time.get_ticks_msec()
	wire.inbound_buffer_size = 8192
	wire.outbound_buffer_size = 8192
	wire.max_queued_packets = 16
	wire.heartbeat_interval = 20
	if wire.connect_to_url(websocket_url("/host")) != OK:
		failed_reported = true
		session.feedback.emit("Online listing unavailable. LAN play is still available.")


func finish() -> void:
	closing = true
	set_process(true)
	if registered and wire.get_ready_state() == WebSocketPeer.STATE_OPEN:
		wire.send_text(JSON.stringify({"type": "unlist"}))


func _exit_tree() -> void:
	wire.close()


func _process(_delta: float) -> void:
	if closing and session.retiring_channels.is_empty():
		queue_free()
		return
	wire.poll()
	var state := wire.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED or (not registered and Time.get_ticks_msec() - started > 15000):
		if closing:
			queue_free()
			return
		if not closing and not failed_reported:
			failed_reported = true
			session.feedback.emit("Online listing unavailable. LAN play is still available.")
		wire.close()
		set_process(false)
		return
	if state != WebSocketPeer.STATE_OPEN:
		return
	if not sent:
		wire.send_text(JSON.stringify({"version": 1, "game": description()}))
		sent = true
	for index in mini(16, wire.get_available_packet_count()):
		var parser := JSON.new()
		if parser.parse(wire.get_packet().get_string_from_utf8()) != OK or not parser.data is Dictionary:
			wire.close()
			return
		var message: Dictionary = parser.data
		if not message.get("type") is String:
			wire.close()
			return
		if message.get("type") == "registered" and MultiplayerLanDiscovery.valid_nonce(message.get("id")) and message.get("token") is String and message.token.length() == 64:
			room = message.id
			secret = message.token
			registered = true
			session.feedback.emit("Game is visible online.")
		elif message.get("type") == "peer" and registered and not closing and MultiplayerLanDiscovery.valid_nonce(message.get("id")):
			if session.channels.size() < CoopSession.MAX_PLAYERS - 1:
				var channel := MultiplayerRelayChannel.new(websocket_url("/host/" + room + "/" + message.id), secret, 65536)
				session.channels[session.next_peer] = channel
				session.handshake_started[session.next_peer] = Time.get_ticks_msec()
				session.next_peer += 1
	if registered and not closing:
		var info := description()
		var encoded := JSON.stringify(info)
		var now := Time.get_ticks_msec()
		if now >= next_update or (encoded != signature and now >= next_update - 19000):
			wire.send_text(JSON.stringify({"type": "update", "game": info}))
			signature = encoded
			next_update = now + 20000


func description() -> Dictionary:
	var data := session.lan_description()
	data.erase("port")
	data.erase("session")
	return data
