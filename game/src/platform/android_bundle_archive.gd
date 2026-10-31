class_name AndroidBundleArchive
extends RefCounted
## Indexed ZIP reads avoid ZIPReader's repeated directory scans on Android.

const MAX_BYTES := 512 * 1024 * 1024
const MAX_ENTRIES := 20000

static var _jni: Object
static var _failed := false


static func valid_name(name: String) -> bool:
	return not name.is_empty() and not name.is_absolute_path() and not name.contains("\\") and ":" not in name and ".." not in name.split("/")


static func _call(object: Object, method: String, arguments := []) -> Variant:
	if _failed or object == null:
		_failed = true
		return null
	var result: Variant = object.callv(method, arguments)
	if _jni.get_exception() != null:
		_failed = true
		return null
	return result


static func _close(object: Object) -> void:
	# Cleanup still runs after an earlier JNI or stream failure.
	if object != null:
		object.call("close")
		if _jni.get_exception() != null:
			_failed = true


static func extract(archive: String, destination: String) -> Error:
	if not OS.has_feature("android") or not Engine.has_singleton("JavaClassWrapper"):
		return ERR_UNAVAILABLE
	_jni = Engine.get_singleton("JavaClassWrapper")
	_failed = false
	var zip_class: Object = _call(_jni, "wrap", ["java.util.zip.ZipFile"])
	var output_class: Object = _call(_jni, "wrap", ["java.io.FileOutputStream"])
	var channels: Object = _call(_jni, "wrap", ["java.nio.channels.Channels"])
	var crc_class: Object = _call(_jni, "wrap", ["java.util.zip.CRC32"])
	var checked_class: Object = _call(_jni, "wrap", ["java.util.zip.CheckedInputStream"])
	var zip: Object = _call(zip_class, "ZipFile", [archive])
	var entries: Object = _call(zip, "entries")
	var total := 0
	var count := 0
	var result := OK
	while not _failed and bool(_call(entries, "hasMoreElements")):
		var entry: Object = _call(entries, "nextElement")
		var name := str(_call(entry, "getName"))
		var size := int(_call(entry, "getSize"))
		count += 1
		if _failed or count > MAX_ENTRIES or size < 0 or size > MAX_BYTES or not valid_name(name):
			result = ERR_FILE_CORRUPT
			break
		total += size
		if total > MAX_BYTES:
			result = ERR_OUT_OF_MEMORY
			break
		if name.ends_with("/"):
			continue
		var target := destination.path_join(name)
		result = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if result != OK:
			break
		var input: Object = _call(zip, "getInputStream", [entry])
		var crc: Object = _call(crc_class, "CRC32")
		var checked: Object = _call(checked_class, "CheckedInputStream", [input, crc])
		var readable: Object = _call(channels, "newChannel", [checked])
		var output: Object = _call(output_class, "FileOutputStream", [target])
		var writable: Object = _call(output, "getChannel")
		var offset := 0
		while not _failed and offset < size:
			var copied := int(_call(writable, "transferFrom", [readable, offset, size - offset]))
			if copied <= 0:
				break
			offset += copied
		var actual_crc := int(_call(crc, "getValue"))
		var expected_crc := int(_call(entry, "getCrc"))
		_close(writable)
		_close(output)
		_close(readable)
		_close(checked)
		_close(input)
		if _failed or offset != size or actual_crc != expected_crc:
			result = ERR_FILE_CORRUPT
			break
	_close(zip)
	return ERR_FILE_CANT_READ if _failed else result
