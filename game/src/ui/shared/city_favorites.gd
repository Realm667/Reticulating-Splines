class_name CityFavorites
extends RefCounted
## City stars are UI preferences, independent of folder history and save contents.

signal changed
var path := ""
var config := ConfigFile.new()


func _init(storage_path := "") -> void:
	path = storage_path if not storage_path.is_empty() else AppPaths.path("city-favorites.cfg")
	config.load(path)


func contains(key: String) -> bool:
	return bool(config.get_value("cities", key, false))


func reload() -> void:
	config.load(path)


func set_favorite(key: String, enabled: bool) -> bool:
	reload()
	var old := contains(key)
	config.set_value("cities", key, enabled)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK or config.save(path) != OK:
		config.set_value("cities", key, old)
		return false
	changed.emit()
	return true


static func local_key(file_path: String) -> String:
	var stored := AppPaths.stored_path(file_path.simplify_path())
	return "local:" + (stored.to_lower() if OS.has_feature("windows") else stored).sha256_text()


static func cloud_key(service: Node, save_id: String) -> String:
	# Do not share stars between accounts or endpoints, even if IDs coincide.
	if service == null or not service.has_method("favorite_scope") or save_id.is_empty():
		return ""
	return "cloud:" + (str(service.favorite_scope()) + "|" + save_id).sha256_text()
