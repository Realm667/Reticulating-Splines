extends SceneTree
## Persistent unlocks and presentation transforms must retain their boundaries.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + description)


func _run() -> void:
	var document := Sc2xDocument.create_empty(128, "Debug grants").document
	check(ExpandedRules.enable(document).is_empty(), "Enable Expanded fixture")
	var city := CityState.from_document(document)
	check(CityDebugActions.unlock_everything(city, document).ok, "Debug unlock succeeds")
	for kind in ExpandedRules.NAMES.size():
		check(ExpandedRules.available(city, kind) and ExpandedRules.visible_reward(city, kind), "Expanded reward granted")
	var saved := document.serialize()
	var restored := Sc2File.new()
	check(saved.ok and restored.parse(saved.data), "Unlocked city round trip")
	for kind in ExpandedRules.NAMES.size():
		check(ExpandedRules.available(CityState.from_document(restored), kind), "Grant survives loading")
	var classic := EmptyCityTemplate.create()
	check(CityDebugActions.unlock_everything(CityState.from_document(classic), classic).ok, "Classic unlock succeeds")
	check(not ExpandedRules.enabled(classic), "Debug does not convert Classic rules")
	var mask := Image.create(3, 1, false, Image.FORMAT_RGBA8)
	mask.set_pixel(0, 0, Color(1, 0.8, 0.4, 168.0 / 255))
	mask.set_pixel(1, 0, Color(1, 0.8, 0.4, 30.0 / 255))
	mask.set_pixel(2, 0, Color(0.3, 1, 1, 1))
	check(CityBrightmaps.window_gain(mask, 1.0) == mask, "Custom mask without gain remains identical")
	var corrected := CityBrightmaps.window_gain(mask, 1.3)
	check(corrected.get_pixel(0, 0).a > 0.85, "Strong windows gain brightness")
	check(corrected.get_pixel(1, 0) == mask.get_pixel(1, 0), "Soft facade illumination is preserved")
	check(corrected.get_pixel(2, 0).a == 1.0, "Neon alpha stays bounded")
	var wire := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	wire.set_pixel(0, 0, Color8(90, 90, 90))
	wire.set_pixel(1, 0, Color8(90, 90, 90))
	wire.set_pixel(4, 4, Color8(156, 156, 156))
	check(CityUndergroundView.clean_wireframe(wire, true).get_pixel(4, 4).a == 0.0, "Known wireframe speck is transparent")
	check(wire.get_pixel(4, 4).a == 1.0, "Source sprite is unchanged")
	wire.set_pixel(3, 3, Color8(110, 110, 110))
	check(CityUndergroundView.clean_wireframe(wire, true) == wire, "Multicolor custom artwork is unchanged")
	AppLocalization.select("de")
	var timestamp := CityLibraryTable.format_timestamp(1794508250.0)
	check(timestamp.contains(":") and not timestamp.contains("1794508250"), "Readable numeric Cloud timestamp")
	check(timestamp == CityLibraryTable.format_timestamp("1794508250.0"), "Float, integer and numeric string share formatting")
	check(CityLibraryTable.format_timestamp(null) == "—", "Missing timestamp stays explicit")
	print("PASS: follow-up unlock persistence, precise emission/wireframe transforms and Cloud timestamps" if failures == 0 else "FAIL: follow-up regressions")
	quit(int(failures > 0))
