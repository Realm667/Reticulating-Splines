class_name ExpandedRules
extends RefCounted
## Permanent city rules and the eight versioned metropolis rewards.

@warning_ignore_start("integer_division")

const FEATURE := "rs.expanded.v1"
const FIRST_TOOL := 9
const FIRST_SPRITE := 4500000
const NAMES := ["National Museum", "Opera House", "Metropolitan Park", "International Convention Center",
	"University Hospital", "National Library", "International Research Center", "World Exhibition Grounds"]
const SLUGS := ["nationalmuseum", "opernhaus", "metropolpark", "kongresszentrum", "universitaetsklinikum",
	"nationalbibliothek", "forschungszentrum", "weltausstellung"]
const AREAS := [4, 4, 5, 4, 4, 3, 5, 6]
const THRESHOLDS := [150000, 250000, 400000, 650000, 1000000, 1500000, 2500000, 4000000]
const COSTS := [0, 0, 0, 25000, 40000, 0, 60000, 0]
const UPKEEP := [120, 240, 120, 600, 1200, 240, 1200, 600]
const EFFECTS := [
	"Adds 25 college capacity and improves nearby land value.",
	"Improves nearby land value, benefiting homes and commerce.",
	"Improves nearby land value over a wide area.",
	"Improves nearby commercial land value.",
	"Adds 100 health capacity, equivalent to four fully funded hospitals.",
	"Adds 45 school capacity, equivalent to three fully funded schools.",
	"Adds 100 college capacity, equivalent to two fully funded colleges.",
	"Improves nearby land value, benefiting homes and commerce.",
]


static func is_reward_tool(group: int, subtool: int) -> bool:
	return group == 5 and subtool >= FIRST_TOOL and subtool < FIRST_TOOL + 8


static func enabled(document: Sc2File) -> bool:
	return document != null and document.find_chunk("XEXP") != null


static func enable(document: Sc2File) -> String:
	if not document.is_sc2x():
		return "Expanded requires an SC2X city."
	if enabled(document):
		return ""
	var data := PackedByteArray()
	data.resize(160)
	data[0] = 69
	data[1] = 88
	data[2] = 80
	data[3] = 49
	BinaryData.write_u32_be(data, 8, document.misc_u32(Sc2MiscLayout.CITY_DAYS) / 25)
	var chunk := Sc2Chunk.new()
	chunk.chunk_id = "XEXP"
	chunk.set_decoded_payload(data)
	document.chunks.append(chunk)
	document.invalidate_chunk_cache()
	if FEATURE not in document.sc2x_metadata.required_features:
		document.sc2x_metadata.required_features.append(FEATURE)
	var city := CityState.from_document(document)
	if not city.is_valid():
		return city.load_error
	NativeSimulationBridge.run("expanded.unlock", city, null, null, null)
	return ""


static func data(city: CityState) -> PackedByteArray:
	if city == null or not enabled(city.document):
		return PackedByteArray()
	return city.document.find_chunk("XEXP").decoded_payload


static func available(city: CityState, kind: int) -> bool:
	var bytes := data(city)
	return bytes.size() == 160 and BinaryData.read_u32_be(bytes, 12) & (1 << kind) != 0 and BinaryData.read_u32_be(bytes, 32 + kind * 16) == 0


static func visible_reward(city: CityState, kind: int) -> bool:
	var bytes := data(city)
	if bytes.size() != 160:
		return false
	var mask := BinaryData.read_u32_be(bytes, 12)
	return kind == 0 or mask & (1 << (kind - 1)) != 0


static func render_records(city: CityState) -> PackedInt32Array:
	var bytes := data(city)
	var records := PackedInt32Array()
	if bytes.size() != 160:
		return records
	for kind in 8:
		var offset := 32 + kind * 16
		if BinaryData.read_u32_be(bytes, offset) == 0:
			continue
		var x := BinaryData.read_u32_be(bytes, offset + 4)
		var y := BinaryData.read_u32_be(bytes, offset + 8)
		# Display copies may hide buildings for a map overlay.
		if city.building_id(x, y) == BuildingTileIds.STATUE:
			records.append_array(PackedInt32Array([kind, x, y, AREAS[kind]]))
	return records


static func at(city: CityState, point: Vector2i) -> int:
	var records := render_records(city)
	for offset in range(0, records.size(), 4):
		if Rect2i(records[offset + 1], records[offset + 2], records[offset + 3], records[offset + 3]).has_point(point):
			return records[offset]
	return -1


static func budget(city: CityState) -> Dictionary:
	var bytes := data(city)
	var annual := 0
	if bytes.size() != 160:
		return {"annual": 0, "ytd": 0, "estimated": 0, "remaining": 0}
	for kind in 8:
		if BinaryData.read_u32_be(bytes, 32 + kind * 16) != 0:
			annual += UPKEEP[kind]
	var ytd := BinaryData.read_u32_be(bytes, 24) if BinaryData.read_u32_be(bytes, 28) == city.age_in_days() / 300 else 0
	# The current month is already settled; newly placed buildings start next month.
	var remaining := annual / 12 * (11 - city.age_in_days() / 25 % 12)
	return {"annual": annual, "ytd": ytd, "estimated": ytd + remaining, "remaining": remaining}


static func details(kind: int) -> String:
	return "%s\n%s\n%s\n%s" % [TranslationServer.translate(EFFECTS[kind]),
		TranslationServer.translate("Unlocks at %s residents, including arcologies.") % DisplayNumberFormat.format(THRESHOLDS[kind]),
		TranslationServer.translate("Annual upkeep: $%d (charged monthly).") % UPKEEP[kind],
		TranslationServer.translate("Requires power and paid upkeep. One per city. Rebuilding keeps the same construction cost.")]


static func operating_status(city: CityState, kind: int) -> String:
	var bytes := data(city)
	if BinaryData.read_u32_be(bytes, 44 + kind * 16) == 0:
		return TranslationServer.translate("Inactive: upkeep not paid.")
	var x := BinaryData.read_u32_be(bytes, 36 + kind * 16)
	var y := BinaryData.read_u32_be(bytes, 40 + kind * 16)
	for dx in AREAS[kind]:
		for dy in AREAS[kind]:
			if city.tile_flags[city.index_of(x + dx, y + dy)] & Sc2TileFlags.POWERED != 0:
				return TranslationServer.translate("Operating: power and upkeep supplied.")
	return TranslationServer.translate("Inactive: no power.")
