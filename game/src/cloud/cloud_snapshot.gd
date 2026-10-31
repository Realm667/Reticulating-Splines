class_name CloudSnapshot
extends RefCounted
## Validates complete save units. Cloud data never becomes a live document until
## the existing city, checkpoint and region readers have accepted it.
@warning_ignore_start("integer_division")

static func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


static func inspect(bytes: PackedByteArray, expected_hash := "", metadata: Dictionary = {}) -> Dictionary:
	if bytes.is_empty() or bytes.size() > Sc2xDocument.MAX_ARCHIVE_BYTES:
		return {"ok": false, "error": "invalid_save"}
	if not expected_hash.is_empty() and digest(bytes) != expected_hash:
		return {"ok": false, "error": "checksum_mismatch"}
	var document := Sc2File.new()
	if not document.parse(bytes) or not document.is_valid():
		return {"ok": false, "error": "invalid_save"}
	if not document.compatibility_error().is_empty():
		return {"ok": false, "error": "incompatible_save"}
	if not compatible_version(str(metadata.get("game_version", ""))):
		return {"ok": false, "error": "incompatible_save"}
	# Gameplay mods are not yet supported. Never silently load a required mod.
	var mods: Variant = metadata.get("mods", [])
	if not mods is Array or not mods.is_empty():
		return {"ok": false, "error": "incompatible_save"}
	if document.is_sc2x():
		if not Sc2xCheckpoint.validate(document.sc2x_metadata.phase_state).is_empty():
			return {"ok": false, "error": "invalid_save"}
		if document.sc2x_extra_entries.has(RegionCampaign.ENTRY):
			var campaign := RegionCampaign.new()
			if not campaign.restore(document).is_empty():
				return {"ok": false, "error": "invalid_save"}
			var campaign_error := _campaign_error(campaign)
			if not campaign_error.is_empty():
				return {"ok": false, "error": campaign_error}
	var kind := "city"
	if document.sc2x_extra_entries.has("multiplayer.json"):
		kind = "multiplayer"
		var session := CoopSession.new()
		session.credential = Crypto.new().generate_random_bytes(24).hex_encode()
		var data: Variant = JSON.parse_string(document.sc2x_extra_entries["multiplayer.json"].get_string_from_utf8())
		var failure := "invalid_save"
		if data is Dictionary and data.get("host") is String:
			# restore transfers only a disposable copy's selected seat; no profile
			# identity or network participant is changed by validation.
			var copy := Sc2File.new()
			if copy.parse(bytes):
				failure = session.restore_embedded(copy, data.host)
		if failure.is_empty() and session.world is SharedWorld:
			if not session.world.template.compatibility_error().is_empty():
				failure = "incompatible_save"
		if failure.is_empty() and session.world is RegionWorld and session.world.campaign != null:
			failure = _campaign_error(session.world.campaign)
		session.free()
		if not failure.is_empty():
			return {"ok": false, "error": "incompatible_save" if failure == "incompatible_save" else "invalid_save"}
	elif document.sc2x_extra_entries.has(RegionCampaign.ENTRY):
		kind = "region"
	var safe := {"name": document.city_name(), "kind": kind,
		"year": document.misc_u32(Sc2MiscLayout.START_YEAR) + document.misc_u32(Sc2MiscLayout.CITY_DAYS) / 300,
		"population": document.misc_u32(Sc2MiscLayout.NORMAL_POPULATION) + document.misc_u32(Sc2MiscLayout.ARCOLOGY_POPULATION),
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"save_format": "sc2x4" if document.is_sc2x() else "sc2", "mods": []}
	var preview := CityPreviewStore.decode(document.sc2x_extra_entries.get(CityPreviewStore.ENTRY, PackedByteArray()))
	if preview != null:
		var scale := minf(384.0 / preview.get_width(), 256.0 / preview.get_height())
		if scale < 1.0:
			preview.resize(maxi(1, int(preview.get_width() * scale)), maxi(1, int(preview.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
		var png := preview.save_png_to_buffer()
		if png.size() <= 96 * 1024:
			safe["preview"] = Marshalls.raw_to_base64(png)
	return {"ok": true, "error": "", "document": document, "metadata": safe}


static func _campaign_error(campaign: RegionCampaign) -> String:
	# Inactive cities do not instantiate simulation controllers during restore.
	# Check their gameplay contract now, before a download replaces any local file.
	for child: Sc2File in campaign.documents.values():
		if not child.compatibility_error().is_empty():
			return "incompatible_save"
		if child.sc2x_metadata == null or not Sc2xCheckpoint.validate(child.sc2x_metadata.phase_state).is_empty():
			return "invalid_save"
	var terrain: Array = campaign.offers.values()
	terrain.append(campaign.template)
	for child: Sc2File in terrain:
		if child == null or not child.compatibility_error().is_empty():
			return "incompatible_save"
	return ""


static func compatible_version(required: String) -> bool:
	if required.is_empty():
		return true # Existing saves predate the cloud manifest; format rules apply.
	var current := str(ProjectSettings.get_setting("application/config/version", ""))
	var expression := RegEx.new()
	expression.compile("^([0-9]+)\\.([0-9]+)\\.([0-9]+)(?:-rs\\.([0-9]+))?(?:-dev\\.([0-9]+))?$")
	var expected := expression.search(required)
	var available := expression.search(current)
	if expected == null or available == null:
		return required == current
	for group in range(1, 5):
		var difference := int(expected.get_string(group)) - int(available.get_string(group))
		if difference != 0:
			return difference < 0
	if expected.get_string(5).is_empty():
		return available.get_string(5).is_empty()
	return available.get_string(5).is_empty() or int(expected.get_string(5)) <= int(available.get_string(5))
