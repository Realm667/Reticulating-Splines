class_name MusicBoxLibrary
extends RefCounted
## Resolve audible files separately from the simulation's numeric music slots.

var tracks: Dictionary = {}
var sources: Dictionary[String, String] = {}


static func valid_key(key: String) -> bool:
	var parts := key.split(":")
	return parts.size() == 2 and parts[0] in ["reticulating", "pack"] and parts[1].is_valid_int() \
		and int(parts[1]) >= MusicDirector.FIRST_TRACK_ID \
		and int(parts[1]) < MusicDirector.FIRST_TRACK_ID + MusicDirector.TRACK_COUNT


static func source_for(pack: MediaPack) -> String:
	if pack.import_revision >= 0:
		return "original"
	if pack.pack_name in ["Standalone Music", "Reticulating Splines"]:
		return "reticulating"
	return "pack"


static func key_for(pack: MediaPack, id: int) -> Variant:
	var source := source_for(pack)
	return id if source == "original" else source + ":" + str(id)


func refresh(data: DataPack, selected: MediaPack, standalone_folder: String) -> void:
	tracks.clear()
	sources.clear()
	var has_original := data != null and data.is_loaded() and data.import_revision >= 0
	if has_original:
		# Imports place data and music alongside each other, even when a replacement
		# pack is currently selected for automatic game music.
		_add_pack(MediaPack.load_folder(data.root.get_base_dir().path_join("music"), "music"), true)
	if FileAccess.file_exists(standalone_folder.path_join("pack.json")):
		var standalone := MediaPack.load_folder(standalone_folder, "music")
		if source_for(standalone) == "reticulating":
			_add_pack(standalone, false)
	_add_pack(selected, has_original)


func _add_pack(pack: MediaPack, allow_original: bool) -> void:
	if pack == null or not pack.error.is_empty():
		return
	var source := source_for(pack)
	if source == "original" and not allow_original:
		return
	var name := "Reticulating Splines" if source == "reticulating" else pack.pack_name
	for id in range(MusicDirector.FIRST_TRACK_ID, MusicDirector.FIRST_TRACK_ID + MusicDirector.TRACK_COUNT):
		var path := str(pack.files.get(id, ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var key: Variant = key_for(pack, id)
		tracks[key] = {"source": source, "name": name, "path": path, "id": id, "pack": pack,
			"title": MusicTrackTitle.resolve(path, id, source == "original")}
		sources[source] = name


func available(key: Variant) -> bool:
	return tracks.has(key) and FileAccess.file_exists(tracks[key].path)
