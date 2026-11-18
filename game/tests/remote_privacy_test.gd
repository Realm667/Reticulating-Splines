extends SceneTree
## Synthetic account fields and temporary paths; never a real account or save.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(not AppPaths.is_api_test_profile())
	assert(not AppPaths.use_api_test_profile("../personal"))
	assert(AppPaths.use_api_test_profile("privacy-%d" % Time.get_ticks_usec()))
	var allowed := AppPaths.path("cities/test.sc2x")
	assert(AppPaths.api_path_allowed(allowed))
	assert(not AppPaths.api_path_allowed(AppPaths.root().path_join("../outside.sc2x")))
	assert(not AppPaths.api_path_allowed(AppPaths.root() + "-sibling/test.sc2x"))
	assert(not AppPaths.api_path_allowed(AppPaths.root().path_join("link/../inside.sc2x")))
	assert(not AppPaths.api_path_allowed("res://main.tscn"))
	assert(not AppPaths.api_path_allowed("relative.sc2x"))
	assert(RemotePrivacy.sanitize(allowed) == allowed)
	assert(RemotePrivacy.sanitize("Error: No city is loaded.") == "Error: No city is loaded.")
	assert(RemotePrivacy.sanitize("Error: No city is loaded.\n  at /Users/synthetic/private/file.js:1") == "Error: No city is loaded.\n[private path]")
	assert(RemotePrivacy.sanitize({"id": "/root/Main/Control"}).id == "/root/Main/Control")
	assert(RemotePrivacy.sanitize("https://example.invalid/guide") == "https://example.invalid/guide")
	if OS.has_feature("windows"):
		var backslashes := allowed.replace("/", "\\")
		assert(RemotePrivacy.sanitize(backslashes) == backslashes)
	assert(not str(RemotePrivacy.sanitize("/root/.ssh/synthetic-private-file")).contains("synthetic-private-file"))
	assert(not str(RemotePrivacy.sanitize("Copied %s then /Users/synthetic/private" % allowed)).contains("synthetic/private"))
	var outside := OS.get_temp_dir().path_join("synthetic-private-file.sc2x")
	assert(not str(RemotePrivacy.sanitize(outside)).contains("synthetic-private-file"))
	assert(not JSON.stringify(RemotePrivacy.sanitize({"token": "synthetic-token", "email": "synthetic@example.invalid"})).contains("synthetic"))
	var panel := CloudPanel.new(true)
	root.add_child(panel)
	panel.password.text = "synthetic-password-for-test"
	panel.code.text = "482619"
	panel.email.text = "synthetic@example.invalid"
	assert(panel.password.secret and not panel.code.secret)
	for field in [panel.password, panel.code, panel.email]:
		assert(RemotePrivacy.sensitive(field))
		var serialized := JSON.stringify(UiProbe.control_data(field, UiProbe.KIND_TEXT))
		assert(not serialized.contains(field.text))
	var texts := JSON.stringify(UiProbe.texts(panel))
	assert(not texts.contains(panel.password.text) and not texts.contains(panel.code.text) and not texts.contains(panel.email.text))
	var normal := LineEdit.new()
	root.add_child(normal)
	normal.text = "A normal city name"
	assert(UiProbe.control_data(normal, UiProbe.KIND_TEXT).value == normal.text)
	normal.secret = true
	assert(not JSON.stringify(UiProbe.control_data(normal, UiProbe.KIND_TEXT)).contains(normal.text))
	normal.free()
	panel.free()
	print("PASS remote privacy: transient account fields, structured text, private paths and profile boundaries")
	quit()
