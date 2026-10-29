class_name CityActivityIdentity
extends RefCounted
## Optional opaque identity: SC2X metadata extension, legacy SC2/SCLG raw chunk.
## No filename, account, device identifier or simulation RNG enters this value.

const CHUNK := "RSID"
const EXTENSION := "rs_activity_city_id"


static func valid(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func read(document: Sc2File) -> String:
	if document == null:
		return ""
	if document.is_sc2x():
		var saved: Variant = document.sc2x_metadata.extensions.get(EXTENSION, "")
		if saved is String and valid(saved):
			return saved
		# Conversion preserves opaque legacy chunks separately from working planes.
		for record: Dictionary in document.sc2x_preserved:
			if record.get("chunk_id") == CHUNK:
				var payload: PackedByteArray = record.get("payload", PackedByteArray())
				var legacy := payload.get_string_from_ascii()
				if valid(legacy):
					return legacy
	var chunk := document.find_chunk(CHUNK)
	if chunk == null:
		return ""
	var value := chunk.decoded_payload.get_string_from_ascii()
	return value if valid(value) else ""


static func ensure(document: Sc2File, legacy := "") -> String:
	var value := read(document)
	if not value.is_empty():
		return value
	return replace(document, legacy if valid(legacy) else Crypto.new().generate_random_bytes(32).hex_encode())


static func replace(document: Sc2File, value := "") -> String:
	if value.is_empty():
		value = Crypto.new().generate_random_bytes(32).hex_encode()
	if document.is_sc2x():
		document.sc2x_metadata.extensions[EXTENSION] = value
		return value
	var chunk := document.find_chunk(CHUNK)
	if chunk == null:
		chunk = Sc2Chunk.new()
		chunk.chunk_id = CHUNK
		document.chunks.append(chunk)
	chunk.is_compressed = false
	chunk.expected_decoded_size = -1
	chunk.set_decoded_payload(value.to_ascii_buffer(), true)
	# Legacy-to-SC2X conversion preserves unknown chunks by their stored bytes.
	chunk.stored_payload = chunk.decoded_payload.duplicate()
	document.rebuild_chunk_cache()
	return value


static func ensure_world(world: CoopWorld, session_id: String, round_number: int) -> void:
	# Match the already published IDs of pre-identity multiplayer saves exactly.
	var prefix := "rs-activity-city-v1:" + session_id + ":"
	if world is SharedWorld:
		prefix += str(round_number) + ":"
		for actor: String in world.actors:
			ensure(world.municipalities[actor].city.document, (prefix + actor).sha256_text())
	else:
		ensure(world.city.document, (prefix + "coop").sha256_text())
