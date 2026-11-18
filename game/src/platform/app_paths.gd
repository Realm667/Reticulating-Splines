class_name AppPaths
extends RefCounted
## Selects the folder for settings, packs, cities, and other user files.
## A "data" folder beside an exported executable selects portable mode. The
## macOS app bundle is signed, thus it always uses the Godot user folder. The
## native platform library holds the rules.

const PORTABLE_FOLDER := "data"

static var _root := ""
static var _portable := false
static var _error := ""
static var _api_test_profile := false


static func root() -> String:
	if _root.is_empty():
		for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			if argument.begins_with("--api-test-profile="):
				if use_api_test_profile(argument.trim_prefix("--api-test-profile=")):
					return _root
		use_executable_folder(OS.get_executable_path().get_base_dir(),
			OS.has_feature("template") and not OS.has_feature("macos") and not OS.has_feature("android"))

	return _root


static func path(relative: String) -> String:
	return root().path_join(relative)


static func is_portable() -> bool:
	root()

	return _portable


## Returns a message when the portable folder cannot be written.
static func error() -> String:
	root()

	return _error


## Selects the root from the executable folder. Tests use a disposable folder.
static func use_executable_folder(folder: String, allow_portable: bool) -> void:
	_api_test_profile = false
	var selected := NativePlatform.app_root(folder, allow_portable, ProjectSettings.globalize_path("user://"))
	_root = selected.root
	_portable = selected.portable
	_error = selected.error
	if OS.has_feature("android"):
		var installed := AndroidBundledPacks.install(_root)
		if installed != OK:
			_error = error_string(installed)


## API sessions use only a named disposable folder under the OS temp directory.
## Select it before constructing the application or reading its preferences.
static func use_api_test_profile(name: String) -> bool:
	if name.is_empty() or name.length() > 64:
		return false
	for character in name:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			return false
	var parent := OS.get_temp_dir().path_join("reticulating-splines-api-" + name)
	var temp := DirAccess.open(OS.get_temp_dir())
	if temp == null or temp.is_link(parent.get_file()):
		return false
	if DirAccess.make_dir_recursive_absolute(parent) != OK:
		return false
	var directory := DirAccess.open(parent)
	if directory == null or directory.is_link(PORTABLE_FOLDER):
		return false
	if DirAccess.make_dir_recursive_absolute(parent.path_join(PORTABLE_FOLDER)) != OK:
		return false
	use_executable_folder(parent, true)
	_api_test_profile = _portable and _error.is_empty()
	return _api_test_profile


static func is_api_test_profile() -> bool:
	root()
	return _api_test_profile


## File operations from the opt-in API cannot leave its disposable data folder.
static func api_path_allowed(value: String) -> bool:
	if not is_api_test_profile() or not value.is_absolute_path():
		return false
	# Check traversal before normalization: a link followed by .. must not
	# disappear before the component-by-component link check below.
	if value.replace("\\", "/").split("/").has(".."):
		return false
	var absolute := value.simplify_path().replace("\\", "/")
	var base := root().simplify_path().replace("\\", "/")
	var comparison := absolute.to_lower() if OS.has_feature("windows") else absolute
	var boundary := base.to_lower() if OS.has_feature("windows") else base
	if not comparison.begins_with(boundary + "/"):
		return false
	var current := base
	for component in absolute.substr(base.length() + 1).split("/"):
		var directory := DirAccess.open(current)
		if directory != null and directory.is_link(component):
			return false
		current = current.path_join(component)
	return true


## Portable settings keep paths in the data folder relative, thus the folder can move
## to a different drive or location.
static func stored_path(value: String) -> String:
	return NativePlatform.stored_path(value, root(), is_portable(), OS.has_feature("windows"))


static func loaded_path(value: String) -> String:
	return NativePlatform.loaded_path(value, root(), is_portable())
