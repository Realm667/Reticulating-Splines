class_name CityPreviewInfo
extends RefCounted
## Read-only saved values. No city simulation or multiplayer session is restored.

@warning_ignore_start("integer_division")

const MULTIPLAYER_ENTRY := "multiplayer.json"
const MAX_MULTIPLAYER_BYTES := 8 * 1024 * 1024


static func archive(path: String) -> Dictionary:
	return CityPreviewStore.read_members(path, {
		Sc2xDocument.METADATA_ENTRY: 1024 * 1024,
		"MISC.bin": Sc2MiscLayout.SIZE,
		MULTIPLAYER_ENTRY: MAX_MULTIPLAYER_BYTES,
		CityPreviewStore.ENTRY: CityPreviewStore.MAX_BYTES,
	})


static func from_archive(archive_data: Dictionary) -> Dictionary:
	var data: Dictionary = archive_data.get("data", {})
	if not data.has(Sc2xDocument.METADATA_ENTRY):
		return {}
	var parsed := Sc2xMetadata.parse_bytes(data[Sc2xDocument.METADATA_ENTRY])
	if not parsed.ok:
		return {}
	var info := {"city_name": parsed.metadata.city_name, "map_size": parsed.metadata.map_size}
	info.expanded = archive_data.sizes.has(Sc2xDocument.entry_name("XEXP"))
	_read_misc(info, data.get("MISC.bin", PackedByteArray()))
	_read_multiplayer(info, archive_data.sizes.has(MULTIPLAYER_ENTRY), data.get(MULTIPLAYER_ENTRY, PackedByteArray()))
	return info


static func from_document(document: Sc2File) -> Dictionary:
	if document == null or not document.is_valid():
		return {}
	var info := {"city_name": document.city_name(), "map_size": document.map_size}
	info.expanded = ExpandedRules.enabled(document)
	var misc := document.find_chunk("MISC")
	if misc != null:
		_read_misc(info, misc.decoded_payload)
	_read_multiplayer(info, document.sc2x_extra_entries.has(MULTIPLAYER_ENTRY),
		document.sc2x_extra_entries.get(MULTIPLAYER_ENTRY, PackedByteArray()))
	return info


static func _read_misc(info: Dictionary, bytes: PackedByteArray) -> void:
	if bytes.size() != Sc2MiscLayout.SIZE:
		return
	var year := BinaryData.read_u32_be(bytes, Sc2MiscLayout.START_YEAR) + BinaryData.read_u32_be(bytes, Sc2MiscLayout.CITY_DAYS) / CityCalendar.DAYS_PER_YEAR
	info.year = year
	info.funds = BinaryData.read_i32_be(bytes, Sc2MiscLayout.FUNDS)
	info.bank_debt = BinaryData.read_u32_be(bytes, Sc2MiscLayout.BONDS) * BondCommand.BOND_VALUE
	info.population = BinaryData.read_u32_be(bytes, Sc2MiscLayout.NORMAL_POPULATION) + BinaryData.read_u32_be(bytes, Sc2MiscLayout.ARCOLOGY_POPULATION)


static func _read_multiplayer(info: Dictionary, present: bool, bytes: PackedByteArray) -> void:
	info.multiplayer = present
	if not present:
		return
	# A large shared/region checkpoint embeds other cities. Presence still tells
	# us this is multiplayer, without decoding megabytes of unrelated city state.
	info.mode = "unknown"
	if not bytes.is_empty() and bytes.size() <= MAX_MULTIPLAYER_BYTES:
		var parser := JSON.new()
		if parser.parse(bytes.get_string_from_utf8()) == OK:
			var data: Variant = parser.data
			if data is Dictionary and data.get("version") == 1 and data.get("members") is Dictionary:
				if data.members.size() >= 1 and data.members.size() <= 8:
					info.players = data.members.size()
				if not data.has("shared"):
					info.mode = "coop"
				elif data.shared is Dictionary:
					info.mode = "region" if data.shared.get("mode") == "region" else "shared"
	# Root MISC is not a total of separate player finances/populations.
	if info.mode != "coop":
		info.erase("funds")
		info.erase("bank_debt")
		info.erase("population")
		info.separate_finances = true
