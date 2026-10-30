class_name RegionBoundary
extends RefCounted
## Regional coastlines and slopes are immutable across two perimeter tile rows.

const ENTRY := "region-boundary.json"
const ERROR := "The outer two tile rows preserve the landscape transition to neighboring city areas."


static func stamp(document: Sc2File) -> void:
	document.sc2x_extra_entries[ENTRY] = '{"version":1,"rings":2}'.to_utf8_buffer()


static func changed(document: Sc2File, written: Dictionary) -> bool:
	if not document.sc2x_extra_entries.has(ENTRY):
		return false
	var edge := document.map_size
	var perimeter := PackedInt32Array()
	for x in edge:
		for y: int in (range(edge) if x < 2 or x >= edge - 2 else [0, 1, edge - 2, edge - 1]):
			perimeter.append(x * edge + y)
	# A square perimeter is invariant under camera rotation, so the saved camera
	# compass cannot turn the protected world edges into editable inner tiles.
	for id: String in ["ALTM", "XTER", "XBIT"]:
		if not written.has(id):
			continue
		var before := document.find_chunk(id).decoded_payload
		var after: PackedByteArray = written[id]
		if before.size() != after.size():
			return true
		for index in perimeter:
			if id == "ALTM":
				# Land and water elevations; do not lock unrelated altitude flags.
				if ((before[index * 2] ^ after[index * 2]) & 3) != 0 or before[index * 2 + 1] != after[index * 2 + 1]:
					return true
			else:
				var mask := 0x3f if id == "XTER" else Sc2TileFlags.WATER | Sc2TileFlags.SALT_WATER
				if ((before[index] ^ after[index]) & mask) != 0:
					return true
	return false
