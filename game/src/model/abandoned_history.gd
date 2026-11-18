class_name AbandonedHistory
extends RefCounted
## Optional RABH records: two little-endian int32s per original footprint.
## First is its top-left cell index; second is the occupied tile plus XBIT flip at bit 8.

@warning_ignore_start("integer_division")

const CHUNK := "RABH"
const CORNERS := [0x80, 0x10, 0x20, 0x40]


static func is_abandoned(id: int) -> bool:
	return id in [138, 139, 170, 171, 172, 173, 196, 197]


static func area(id: int) -> int:
	if id >= 112 and id <= 135:
		return 1
	if id >= 140 and id <= 165:
		return 2
	if id >= 174 and id <= 193:
		return 3
	return 0


static func records(document: Sc2File) -> PackedInt32Array:
	var chunk := document.find_chunk(CHUNK)
	if chunk == null or chunk.decoded_payload.size() % 8 != 0:
		return PackedInt32Array()
	return chunk.decoded_payload.to_int32_array()


static func store(document: Sc2File, data: PackedInt32Array) -> void:
	var chunk := document.find_chunk(CHUNK)
	if chunk == null:
		if data.is_empty():
			return
		chunk = Sc2Chunk.new()
		chunk.chunk_id = CHUNK
		document.chunks.append(chunk)
		document.invalidate_chunk_cache()
	chunk.set_decoded_payload(data.to_byte_array(), true)


static func _intact(buildings: PackedByteArray, edge: int, index: int, size: int) -> bool:
	if size <= 0 or index < 0 or index / edge + size > edge or index % edge + size > edge:
		return false
	for dx in size:
		for dy in size:
			if not is_abandoned(buildings[index + dx * edge + dy]):
				return false
	return true


## Call after the transaction succeeds and before replacing the old city mirrors.
static func reconcile(city: CityState, after: PackedByteArray, turn := 0, single_anchor := -1) -> void:
	var before := city.buildings
	var edge := city.map_size
	if after.size() != before.size() or before.size() != edge * edge:
		return
	var old := records(city.document)
	var kept := PackedInt32Array()
	for at in range(0, old.size(), 2):
		var index := old[at]
		var size := area(old[at + 1] & 255)
		if turn != 0:
			if size == 0 or index < 0 or index >= before.size():
				continue
			var p := Vector2i(index / edge, index % edge)
			p = Vector2i(p.y, edge - p.x - size) if turn > 0 else Vector2i(edge - p.y - size, p.x)
			index = p.x * edge + p.y
		if _intact(after, edge, index, size):
			kept.append(index)
			kept.append(old[at + 1])
	if turn == 0:
		var corner: int = CORNERS[city.compass_rotation()]
		var anchors := PackedInt32Array([single_anchor]) if single_anchor >= 0 else NativeCityArrays.abandoned_anchors(before, after, city.zones, corner)
		for anchor in anchors:
			var tile := int(before[anchor])
			var size := area(tile)
			var index := anchor - size + 1
			if before[anchor] == after[anchor] or (size > 1 and (city.zones[anchor] & corner) == 0) or not _intact(after, edge, index, size):
				continue
			kept.append(index)
			kept.append(tile | ((city.tile_flags[anchor] & 2) << 7))
	if kept != old:
		store(city.document, kept)
