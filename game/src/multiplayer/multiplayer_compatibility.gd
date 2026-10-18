class_name MultiplayerCompatibility
extends Node
## A bounded, credential-free probe. No seat or city snapshot is requested.

signal completed(error: String)

var channel: CityTcpChannel
var deadline := 0
var nonce := ""


func check_host(address: String, port: int) -> void:
	cancel()
	nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	var socket := StreamPeerTCP.new()
	if socket.connect_to_host(address, port) != OK:
		completed.emit("Compatibility check failed. Check the host address and connection.")
		return
	channel = CityTcpChannel.new(socket, 4096)
	channel.send({"type": "compatibility", "nonce": nonce})
	deadline = Time.get_ticks_msec() + 5000


func _process(_delta: float) -> void:
	if channel == null:
		return
	var messages := channel.poll(1)
	if not messages.is_empty():
		var error := response_error(messages[0], nonce)
		cancel()
		completed.emit(error)
	elif channel.failed or Time.get_ticks_msec() >= deadline:
		cancel()
		completed.emit("Compatibility check failed. Check the host address and connection.")


static func response_error(message: Dictionary, expected_nonce: String) -> String:
	if message.get("type") != "compatibility" or message.get("nonce") != expected_nonce or not message.get("open") is bool:
		return "Compatibility check failed. Check the host address and connection."
	if message.get("protocol") != CoopSession.PROTOCOL or message.get("build") != CoopSession.NETWORK_BUILD:
		return "Different game version"
	if not message.open:
		return "Full"
	return ""


func cancel() -> void:
	if channel != null:
		channel.close()
		channel = null


func _exit_tree() -> void:
	cancel()
