extends SceneTree

var failures := 0


func _initialize() -> void:
	var root := "user://android-bundle-test"
	DirAccess.make_dir_recursive_absolute(root)
	var archive := root.path_join("packs.zip")
	var writer := ZIPPacker.new()
	writer.open(archive)
	writer.start_file("graphic/reticulating-splines/pack.json")
	writer.write_file("{\"version\":1}".to_utf8_buffer())
	writer.close_file()
	writer.close()
	check(AndroidBundledPacks.install(root, archive) == OK, "extracts bundled files into private data")
	var original := AndroidBundledPacks.installed_root
	check(FileAccess.get_file_as_string(original.path_join("graphic/reticulating-splines/pack.json")) == "{\"version\":1}", "native reader receives ordinary file bytes")
	check(AndroidBundledPacks.install(root, archive) == OK and AndroidBundledPacks.installed_root == original, "same immutable bundle reuses completed installation")
	writer.open(archive)
	writer.start_file("../outside.txt")
	writer.write_file("invalid".to_utf8_buffer())
	writer.close_file()
	writer.close()
	check(AndroidBundledPacks.install(root, archive) == ERR_FILE_CORRUPT, "rejects path traversal")
	check(not FileAccess.file_exists(root.path_join("outside.txt")), "writes no path outside bundle root")
	check(FileAccess.file_exists(original.path_join("complete")), "failed update preserves previous bundle")
	check(AndroidBundledPacks.install(root, root.path_join("missing.zip")) == ERR_FILE_NOT_FOUND, "missing archive is reported")
	print("Android bundle: %d failure(s)" % failures)
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
