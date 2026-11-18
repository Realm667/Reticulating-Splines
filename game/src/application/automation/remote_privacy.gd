class_name RemotePrivacy
extends RefCounted
## Structured developer diagnostics must not expose transient account fields.


static func sensitive(control: Node) -> bool:
	if control is LineEdit and (control as LineEdit).secret:
		return true
	return bool(control.get_meta(&"private_diagnostics", false))


static func visible_sensitive(node: Node) -> bool:
	if node is Window and not (node as Window).visible:
		return false
	if node is Control and (node as Control).is_visible_in_tree() and sensitive(node):
		return true
	for child in node.get_children(true):
		if visible_sensitive(child):
			return true
	return false


static func sanitize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			var name := str(key).to_lower()
			if name == "id" and value[key] is String and str(value[key]).begins_with("/root/"):
				result[key] = value[key]
			else:
				result[key] = "[private]" if name == "email" or name.contains("password") or name.contains("token") or name.contains("credential") else sanitize(value[key])
		return result
	if value is Array or value is PackedStringArray:
		var result := []
		for item: Variant in value:
			result.append(sanitize(item))
		return result
	if value is String:
		var text := str(value)
		if text.contains("\n"):
			var lines := PackedStringArray()
			for line in text.split("\n"):
				lines.append(str(sanitize(line)))
			return "\n".join(lines)
		var absolute_path := RegEx.new()
		absolute_path.compile("\\A(?:[A-Za-z]:[\\\\/]|[\\\\/]|res://|user://)")
		if absolute_path.search(text) != null:
			return value if AppPaths.api_path_allowed(text) else "[private path]"
		var private_path := RegEx.new()
		private_path.compile("(\\b[A-Za-z]:[\\\\/]|/Users/|/home/|/root/)")
		var remainder := text.replace(AppPaths.root(), "[test profile]").replace(AppPaths.root().replace("/", "\\"), "[test profile]")
		if private_path.search(remainder) != null:
			return "[private path]"
	return value
