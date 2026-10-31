class_name AndroidBundledPacks
extends RefCounted
## Android assets live inside the APK. Native readers need ordinary private files.

static var installed_root := ""


static func install(user_root: String, archive := "res://android-packs.zip") -> Error:
	var digest := FileAccess.get_file_as_string(archive + ".sha256").strip_edges() if FileAccess.file_exists(archive + ".sha256") else FileAccess.get_sha256(archive)
	if digest.is_empty():
		return ERR_FILE_NOT_FOUND
	var destination := user_root.path_join("bundled").path_join(digest)
	if FileAccess.file_exists(destination.path_join("complete")):
		installed_root = destination
		return OK
	# Seeking backwards in a compressed APK asset re-inflates the outer archive.
	# Copy once to a private regular file before ZIPReader seeks among its entries.
	var local_archive := user_root.path_join("bundled-packs.install.zip")
	var error := DirAccess.make_dir_recursive_absolute(user_root)
	if error != OK:
		return error
	var source := FileAccess.open(archive, FileAccess.READ)
	var target_archive := FileAccess.open(local_archive, FileAccess.WRITE)
	if source == null or target_archive == null:
		return FileAccess.get_open_error()
	if source.get_length() > 512 * 1024 * 1024:
		return ERR_FILE_CORRUPT
	# One read also avoids repeated underlying APK seek/decompression per chunk.
	var archive_bytes := source.get_buffer(source.get_length())
	if archive_bytes.size() != source.get_length():
		return ERR_FILE_CANT_READ
	target_archive.store_buffer(archive_bytes)
	archive_bytes.clear()
	target_archive.flush()
	error = target_archive.get_error()
	target_archive.close()
	source.close()
	if error != OK:
		return error
	if FileAccess.get_sha256(local_archive) != digest:
		return ERR_FILE_CORRUPT
	var reader := ZIPReader.new()
	error = reader.open(local_archive)
	if error != OK:
		return error
	var total := 0
	var files := reader.get_files()
	if files.size() > 20000:
		reader.close()
		return ERR_FILE_CORRUPT
	for name: String in files:
		if name.is_absolute_path() or name.contains("\\") or ":" in name or ".." in name.split("/"):
			reader.close()
			return ERR_FILE_CORRUPT
		if name.ends_with("/"):
			continue
		var bytes := reader.read_file(name)
		total += bytes.size()
		if total > 512 * 1024 * 1024:
			reader.close()
			return ERR_OUT_OF_MEMORY
		var target := destination.path_join(name)
		error = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if error != OK:
			reader.close()
			return error
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			return FileAccess.get_open_error()
		file.store_buffer(bytes)
		file.flush()
		error = file.get_error()
		file.close()
		if error != OK:
			reader.close()
			return error
	reader.close()
	DirAccess.remove_absolute(local_archive)
	var marker := FileAccess.open(destination.path_join("complete"), FileAccess.WRITE)
	if marker == null:
		return FileAccess.get_open_error()
	marker.store_string(digest)
	marker.close()
	installed_root = destination
	return OK
