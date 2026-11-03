class_name PackLibrary
extends RefCounted
## Read-only discovery. Loading and activation stay with the category's loader.
## Never traverse links or scan unrelated application folders.

const FOLDERS := {"graphics": "graphic", "sound": "sounds", "music": "music",
	"data": "data", "hd": "hd", "brightmaps": "brightmaps", "cities": "cities", "mods": "mods"}
const FORMATS := {"graphics": "opensc2k-graphics", "sound": "opensc2k-sound",
	"music": "opensc2k-music", "data": "opensc2k-data", "hd": "opensc2k-hd-sprites"}
const MAX_MANIFEST_BYTES := 8 * 1024 * 1024


static func import_root() -> String:
	return AppPaths.path("pack/sc2000")


static func is_music_package(folder: String) -> bool:
	return _read_json(folder.path_join("pack.json")).get("format") == "opensc2k-music"


static func application_pack_root() -> String:
	if OS.has_feature("android"):
		AppPaths.root()
		return AndroidBundledPacks.installed_root
	if OS.has_feature("template") and OS.has_feature("macos"):
		return OS.get_executable_path().get_base_dir().path_join("../Resources/bundled-packs").simplify_path()
	return ""


static func bundled_folder(kind: String, root := AppPaths.root(), application_root := application_pack_root()) -> String:
	var relative := str(FOLDERS[kind]) + "/reticulating-splines"
	var structured := root.path_join(relative)
	if FileAccess.file_exists(structured.path_join("pack.json")):
		return structured
	var legacy := "standalone-graphics/graphics" if kind == "graphics" else "standalone-audio/" + kind
	var previous := root.path_join("packs/" + legacy)
	if FileAccess.file_exists(previous.path_join("pack.json")):
		return previous
	if not application_root.is_empty():
		var supplied := application_root.path_join(relative)
		if FileAccess.file_exists(supplied.path_join("pack.json")):
			return supplied
	return previous


static func default_folder(kind: String) -> String:
	# Preserve the previous automatic selection when it exists. Merely scanning
	# new folders must not switch a player's soundtrack or graphics.
	var legacy := AppPaths.path("packs/" + kind)
	if FileAccess.file_exists(legacy.path_join("pack.json")):
		return legacy
	if kind in ["graphics", "sound", "music"]:
		var bundled := bundled_folder(kind)
		if FileAccess.file_exists(bundled.path_join("pack.json")):
			return bundled
	return legacy


static func ensure_folders() -> Error:
	for folder: String in FOLDERS.values():
		var error := DirAccess.make_dir_recursive_absolute(AppPaths.path(folder))
		if error != OK:
			return error
	return DirAccess.make_dir_recursive_absolute(import_root())


static func normalized(path: String, kind: String) -> String:
	if kind == "data" and path == DataPack.BUILTIN_SOURCE:
		return path
	if path.is_empty():
		return ""
	var full := path if path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://") else AppPaths.path(path)
	if kind in FORMATS and full.get_file() != "pack.json":
		full = full.path_join("pack.json")
	return ProjectSettings.globalize_path(full).replace("\\", "/").simplify_path()


static func scan(kind: String, selected := "", root := AppPaths.root()) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FOLDERS.has(kind):
		return result
	var seen := {}
	var category_root := root.path_join(FOLDERS[kind])
	if kind in ["cities", "mods"] and DirAccess.dir_exists_absolute(category_root):
		_append(result, seen, kind, category_root)
	var directory := DirAccess.open(category_root)
	if directory != null:
		for name in directory.get_directories():
			if not directory.is_link(name) and not name.begins_with(".") and not name.ends_with(".staging"):
				_append(result, seen, kind, category_root.path_join(name))
	# Older installations and versioned imports remain available in every category.
	if kind in FORMATS or kind == "cities":
		for source in [root.path_join("packs"), root.path_join("pack/sc2000")]:
			_scan_legacy(result, seen, kind, source, 0)
	if kind == "brightmaps" and FileAccess.file_exists(root.path_join("brightmaps-standard/catalog.json")):
		_append(result, seen, kind, root.path_join("brightmaps-standard"))
	if kind in ["graphics", "sound", "music"]:
		var supplied := bundled_folder(kind, root)
		if FileAccess.file_exists(supplied.path_join("pack.json")):
			_append(result, seen, kind, supplied)
	if not selected.is_empty() and not (kind == "data" and selected == DataPack.BUILTIN_SOURCE):
		_append(result, seen, kind, selected)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order := str(a.name).naturalnocasecmp_to(str(b.name))
		return str(a.path) < str(b.path) if order == 0 else order < 0)
	return result


static func selection_entries(kind: String, selected := "", root := AppPaths.root()) -> Array[Dictionary]:
	var groups := {}
	var chosen := normalized(selected, kind)
	for item in scan(kind, selected, root):
		var manifest := _read_json(str(item.path))
		var platform := str(manifest.get("source_platform", ""))
		var folder := str(item.path).get_base_dir()
		var relative := folder.trim_prefix(ProjectSettings.globalize_path(root).replace("\\", "/").simplify_path() + "/")
		var identity := str(item.path)
		if not platform.is_empty() and manifest.has("import_revision"):
			identity = "sc2000:" + platform.to_lower()
			item.name = "SimCity 2000 (%s)" % platform
		elif relative == str(FOLDERS[kind]) + "/reticulating-splines" or relative in ["packs/standalone-graphics/graphics", "packs/standalone-audio/" + kind]:
			identity = "reticulating-splines"
			item.name = "Reticulating Splines"
		# Preserve the active source. Otherwise prefer a valid, newer import,
		# with the structured layout winning ties over a legacy copy.
		item.rank = [int(str(item.path).nocasecmp_to(chosen) == 0), int(str(item.error).is_empty()),
			int(manifest.get("import_revision", 0)), int(not relative.begins_with("packs/"))]
		if not groups.has(identity) or _prefer_entry(item, groups[identity]):
			groups[identity] = item
	var result: Array[Dictionary] = []
	result.assign(groups.values())
	if kind == "data":
		result.append({"name": "Reticulating Splines", "path": DataPack.BUILTIN_SOURCE, "error": ""})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return result


static func _prefer_entry(candidate: Dictionary, previous: Dictionary) -> bool:
	for index in candidate.rank.size():
		if candidate.rank[index] != previous.rank[index]:
			return candidate.rank[index] > previous.rank[index]
	return str(candidate.path) > str(previous.path)


static func _scan_legacy(result: Array[Dictionary], seen: Dictionary, kind: String, folder: String, depth: int) -> void:
	var directory := DirAccess.open(folder)
	if directory == null or depth > 3:
		return
	if FileAccess.file_exists(folder.path_join("pack.json")):
		var manifest := _read_json(folder.path_join("pack.json"))
		if manifest.get("format") == FORMATS.get(kind, ""):
			_append(result, seen, kind, folder)
		if kind == "cities" and manifest.get("format") == "opensc2k-data" and DirAccess.dir_exists_absolute(folder.path_join("CITIES")):
			_append(result, seen, kind, folder.path_join("CITIES"))
		return
	for name in directory.get_directories():
		if not directory.is_link(name) and not name.begins_with(".") and not name.ends_with(".staging"):
			_scan_legacy(result, seen, kind, folder.path_join(name), depth + 1)


static func _append(result: Array[Dictionary], seen: Dictionary, kind: String, path: String) -> void:
	var canonical := normalized(path, kind)
	var identity := canonical.to_lower() if OS.has_feature("windows") else canonical
	if seen.has(identity):
		return
	seen[identity] = true
	result.append(inspect(kind, canonical))


static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_MANIFEST_BYTES:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


static func inspect(kind: String, path: String) -> Dictionary:
	var canonical := normalized(path, kind)
	var folder := canonical.get_base_dir() if kind in FORMATS else canonical
	var item := {"path": canonical, "name": folder.get_file(), "error": ""}
	if not DirAccess.dir_exists_absolute(folder):
		item.error = TranslationServer.translate("Folder not found")
		return item
	if kind == "cities":
		return item
	if kind == "mods":
		var mods := ModCatalog.scan(folder, str(ProjectSettings.get_setting("application/config/version", "")))
		if mods.is_empty():
			item.error = TranslationServer.translate("No mod manifests found")
		for mod in mods:
			if mods.size() == 1:
				item.name = mod.name
			if not mod.error.is_empty():
				item.error = mod.error
		return item
	var manifest_path := folder.path_join("catalog.json" if kind == "brightmaps" else "pack.json")
	var manifest := _read_json(manifest_path)
	if manifest.is_empty():
		item.error = TranslationServer.translate("Missing or invalid manifest")
		return item
	if manifest.get("name") is String and not str(manifest.name).strip_edges().is_empty():
		item.name = manifest.name
	if kind == "brightmaps":
		if not manifest.get("sprites") is Dictionary:
			item.error = TranslationServer.translate("Missing or invalid manifest")
		return item
	if manifest.get("format") != FORMATS.get(kind) or manifest.get("version") != 1 or not manifest.get("name") is String or str(manifest.get("name", "")).strip_edges().is_empty():
		item.error = TranslationServer.translate("Incompatible package format")
		return item
	if kind in ["sound", "music"]:
		var checked := NativePacks.media_manifest(JSON.stringify(manifest), kind, folder)
		item.error = checked.error
		if str(item.error).is_empty():
			for file: String in checked.paths:
				if not FileAccess.file_exists(file):
					item.error = TranslationServer.translate("Missing file: %s") % file.get_file()
					break
	elif kind == "data":
		for file: String in DataPack.REQUIRED_FILES:
			if not FileAccess.file_exists(folder.path_join(file)):
				item.error = TranslationServer.translate("Missing file: %s") % file
				break
	else:
		# Do not decode thousands of sprites to build a menu. The actual loader
		# validates pixels/geometry before activation and retains the previous pack.
		item.error = _missing_images(manifest, folder)
	return item


static func _missing_images(value: Variant, folder: String, depth := 0) -> String:
	if depth > 24:
		return TranslationServer.translate("Missing or invalid manifest")
	if value is String and str(value).get_extension().to_lower() == "png":
		var relative := str(value).replace("\\", "/")
		if relative.is_absolute_path() or ".." in relative.split("/") or not FileAccess.file_exists(folder.path_join(relative)):
			return TranslationServer.translate("Missing file: %s") % relative
	elif value is Dictionary or value is Array:
		for child: Variant in (value.values() if value is Dictionary else value):
			var error := _missing_images(child, folder, depth + 1)
			if not error.is_empty():
				return error
	return ""
