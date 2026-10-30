class_name MultiplayerDocument
extends RefCounted
## Immutable display snapshots of working chunks, without a ZIP save/load cycle.
## The reliable delta codec pages these fields before any compression or JSON work.

const PREFIX := "chunk/"
const EXTRA := "chunk/extra"
const EXTRA_FIELDS := ["sc2x_compat_labels", "sc2x_object_ids", "sc2x_object_kinds",
	"sc2x_object_names", "sc2x_extensions", "sc2x_text_orders", "sc2x_preserved",
	"sc2x_extra_entries", "sc2x_unsupported_features", "sc2x_converted_from"]
var buffers: Dictionary = {}
var texts: Dictionary = {}
var page_versions: Dictionary = {}
var generation := 0
const RAW_PAGE := 3072 # Exactly 4096 base64 characters; never split a triplet.


func capture(document: Sc2File, shared: MultiplayerDocument = null, shared_ids: Array = []) -> Dictionary:
	document.reconcile_object_identities()
	var layout: Array = []
	var result := {}
	var versions := {}
	for index in document.chunks.size():
		var chunk := document.chunks[index]
		var key := PREFIX + str(index)
		layout.append([chunk.chunk_id, chunk.decoded_payload.size()])
		result[key] = shared.encode_buffer(chunk.chunk_id, chunk.decoded_payload) if shared != null and chunk.chunk_id in shared_ids else encode_buffer(key, chunk.decoded_payload)
		versions[key] = shared.page_versions[chunk.chunk_id] if shared != null and chunk.chunk_id in shared_ids else page_versions[key]
	var extras := {}
	for field: String in EXTRA_FIELDS:
		extras[field] = document.get(field)
	# Never expose the private session/reconnect identities as a public extra.
	extras.sc2x_extra_entries = extras.sc2x_extra_entries.duplicate()
	extras.sc2x_extra_entries.erase("multiplayer.json")
	for entry: String in extras.sc2x_extra_entries.keys():
		if entry == RegionCampaign.ENTRY or entry == RegionCampaign.TEMPLATE_ENTRY or entry.begins_with(RegionCampaign.PREFIX):
			extras.sc2x_extra_entries.erase(entry)
	result[EXTRA] = encode_buffer(EXTRA, var_to_bytes(extras))
	versions[EXTRA] = page_versions[EXTRA]
	result["chunk_pages"] = versions
	result["document"] = {"size": document.map_size, "layout": layout,
		"metadata": document.sc2x_metadata.to_json()}
	for key: String in buffers.keys():
		if not result.has(key):
			buffers.erase(key)
			texts.erase(key)
			page_versions.erase(key)
	return result


func encode_buffer(key: String, bytes: PackedByteArray) -> String:
	if buffers.get(key) != bytes:
		generation += 1
		var old: PackedByteArray = buffers.get(key, PackedByteArray())
		var old_versions: Array = page_versions.get(key, {}).get("pages", [])
		var versions: Array = []
		var parts := PackedStringArray()
		for offset in range(0, bytes.size(), RAW_PAGE):
			@warning_ignore("integer_division")
			var page := offset / RAW_PAGE
			var part := bytes.slice(offset, offset + RAW_PAGE)
			# Native byte comparison also covers imported/borrowed raw-buffer edits.
			# Its result is reused by every recipient's worker delta codec.
			if page < old_versions.size() and part == old.slice(offset, offset + RAW_PAGE):
				versions.append(old_versions[page])
				parts.append(str(texts[key]).substr(page * MultiplayerDelta.PAGE, MultiplayerDelta.PAGE))
			else:
				versions.append(generation)
				parts.append(Marshalls.raw_to_base64(part))
		buffers[key] = bytes.duplicate()
		texts[key] = "".join(parts)
		page_versions[key] = {"epoch": str(get_instance_id()), "pages": versions}
	return texts[key]


static func view_copy(source: Sc2File) -> Sc2File:
	# Used synchronously for composing a display snapshot. The raw input buffers
	# are read-only until capture has taken its own immutable comparison copies.
	var result := Sc2File.new()
	result.map_size = source.map_size
	result.large_version = source.large_version
	result.sc2x_metadata = source.sc2x_metadata.copy()
	for field: String in EXTRA_FIELDS:
		var value: Variant = source.get(field)
		result.set(field, value.duplicate(true) if value is Dictionary or value is Array else value.duplicate() if not value is String else value)
	for original in source.chunks:
		var chunk := Sc2Chunk.new()
		chunk.chunk_id = original.chunk_id
		chunk.expected_decoded_size = original.expected_decoded_size
		chunk.decoded_payload = original.decoded_payload
		chunk.mutation_revision = original.mutation_revision
		chunk.is_dirty = true
		result.chunks.append(chunk)
	result.rebuild_chunk_cache()
	return result


static func restore(state: Dictionary, previous: Dictionary = {}, old: Sc2File = null) -> Sc2File:
	var descriptor: Variant = state.get("document")
	if not descriptor is Dictionary or not descriptor.get("layout") is Array or descriptor.layout.size() > 4096:
		return null
	if not CoopWorld.whole_number(descriptor.get("size"), 16, 4096) or int(descriptor.size) not in Sc2File.MAP_SIZES:
		return null
	if not descriptor.get("metadata") is String:
		return null
	var metadata := Sc2xMetadata.parse(descriptor.metadata)
	if not metadata.ok or metadata.metadata.map_size != int(descriptor.size):
		return null
	var document := Sc2File.new()
	document.large_version = 4
	document.map_size = int(descriptor.size)
	document.sc2x_metadata = metadata.metadata
	var total := 0
	var seen := {}
	for index in descriptor.layout.size():
		var item: Variant = descriptor.layout[index]
		var key := PREFIX + str(index)
		if not item is Array or item.size() != 2 or not item[0] is String or item[0].length() != 4 or not CoopWorld.whole_number(item[1], 0, Sc2xDocument.MAX_DATA_BYTES) or not state.get(key) is String:
			return null
		if seen.has(item[0]) and item[0] in Sc2xDocument.REQUIRED_ENTRIES:
			return null
		seen[item[0]] = true
		total += int(item[1])
		if total > Sc2xDocument.MAX_DATA_BYTES or state[key].length() != 4 * ceili(float(item[1]) / 3.0):
			return null
		if old != null and old.map_size == document.map_size and index < old.chunks.size() and old.chunks[index].chunk_id == item[0] and state[key] == previous.get(key) and old.chunks[index].decoded_payload.size() == int(item[1]):
			document.chunks.append(old.chunks[index])
			continue
		var chunk := Sc2Chunk.new()
		chunk.chunk_id = item[0]
		chunk.decoded_payload = Marshalls.base64_to_raw(state[key])
		if chunk.decoded_payload.size() != int(item[1]):
			return null
		chunk.expected_decoded_size = int(item[1])
		chunk.is_dirty = true
		document.chunks.append(chunk)
	document.rebuild_chunk_cache()
	for id: String in Sc2xDocument.REQUIRED_ENTRIES:
		var chunk := document.find_chunk(id)
		if chunk == null:
			return null
		var expected := document.decoded_size(id)
		if expected >= 0 and chunk.decoded_payload.size() != expected:
			return null
		var stride := Sc2MicrosimLayout.RECORD_SIZE if id == "XMIC" else Sc2ThingLayout.RECORD_SIZE if id == "XTHG" else Sc2LabelLayout.record_size_of(chunk.decoded_payload) if id == "XLAB" else 1
		if chunk.decoded_payload.size() % stride != 0:
			return null
	if not state.get(EXTRA) is String or state[EXTRA].length() > Sc2xDocument.MAX_DATA_BYTES:
		return null
	var extras: Variant = bytes_to_var(Marshalls.base64_to_raw(state[EXTRA]))
	if not extras is Dictionary or extras.size() != EXTRA_FIELDS.size():
		return null
	for field: String in EXTRA_FIELDS:
		if not extras.has(field) or typeof(extras[field]) != typeof(document.get(field)):
			return null
	# Rebuild typed containers explicitly after the object-free binary decoder.
	for field: String in EXTRA_FIELDS:
		if extras[field] is Dictionary:
			var value: Dictionary = document.get(field)
			for key: Variant in extras[field]:
				if not key is String or not extras[field][key] is PackedByteArray:
					return null
				value[key] = extras[field][key]
		elif field == "sc2x_preserved":
			for record: Variant in extras[field]:
				if not record is Dictionary:
					return null
				document.sc2x_preserved.append(record)
		else:
			document.set(field, extras[field])
	if document.sc2x_extra_entries.has("multiplayer.json"):
		return null
	for entry: String in document.sc2x_extra_entries:
		if entry == RegionCampaign.ENTRY or entry == RegionCampaign.TEMPLATE_ENTRY or entry.begins_with(RegionCampaign.PREFIX):
			return null
	return document
