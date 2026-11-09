extends SceneTree
## Timed upgrades, save identity, undo and authoritative multiplayer commands.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	var document := Sc2xDocument.create_empty(64, "Upgrade test").document
	check(ExpandedRules.enable(document).is_empty(), "enable")
	document.set_misc_u32(Sc2MiscLayout.START_YEAR, 1950)
	document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 100000)
	var city := CityState.from_document(document)
	city.set_funds(1000000)
	var rng := SimRandom.new(123)
	var lfsr := SimLfsrRandom.new(17)
	var point := Vector2i(12, 12)
	var built := BuildingCommand.apply(city, 13, 0, point, lfsr, rng)
	check(built.ok, "place police: " + built.error)
	var info := BuildingUpgrades.info(city, point)
	check(not info.is_empty() and info.level == 0 and info.cost == 875, "first level quote")
	if info.is_empty():
		quit(1)
		return
	var money := city.funds()
	var edit := BuildingUpgrades.apply(city, point, 0, 0)
	check(edit.ok, "upgrade: " + edit.error)
	check(city.funds() == money - 875, "cost once")
	check(not BuildingUpgrades.apply(city, point, 0, 0).ok, "duplicate rejected")
	check(NativeToolEdit.undo(city, edit, "upgrade", "upgrade", 9).ok, "undo")
	check(city.funds() == money and BuildingUpgrades.info(city, point).identity == 0, "undo restores work and funds")
	edit = BuildingUpgrades.apply(city, point, 0, 0)
	check(edit.ok, "restart")
	var serialized := document.serialize()
	check(serialized.ok, "save under construction: " + serialized.error)
	var loaded := Sc2File.new()
	check(loaded.parse(serialized.data), "load")
	city = CityState.from_document(loaded)
	check(city.is_valid(), city.load_error)
	info = BuildingUpgrades.info(city, point)
	check(info.target == 1 and info.remaining == 75 and info.level == 0, "timing and identity survive save")
	loaded.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 74)
	NativeSimulationBridge.run("milestones", city, null, null, null)
	check(BuildingUpgrades.info(city, point).level == 0, "not complete early")
	loaded.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 75)
	NativeSimulationBridge.run("milestones", city, null, null, null)
	check(BuildingUpgrades.info(city, point).level == 1, "completion")
	var original := loaded.find_chunk("XUPG").decoded_payload.duplicate()
	for turn in 4:
		check(CityRotationCommand.apply(city, false).ok, "rotate")
		check(CityState.from_document(loaded).is_valid(), "rotation validity")
	check(original == loaded.find_chunk("XUPG").decoded_payload, "rotation round trip")
	var removed := DemolishCommand.apply_path(city, 0, 0, [point], rng)
	check(removed.ok and loaded.find_chunk("XUPG").decoded_payload.size() == 24, "demolition loses upgrade")
	check(DemolishCommand.undo(city, removed, rng).ok, "demolition undo")
	check(BuildingUpgrades.info(city, point).level == 1, "demolition undo restores level")
	var world := CoopWorld.new()
	check(world.open(loaded), "coop initialize")
	var request := {"kind": "upgrade", "start": [12, 12], "finish": [12, 12], "identity": int(info.identity), "level": 1, "revision": world.revision}
	var response := world.command("owner", request)
	check(response.get("ok", false), "host upgrade: " + str(response))
	var host_funds := world.city.funds()
	check(not world.command("owner", request).get("ok", false), "stale host request rejected")
	check(world.city.funds() == host_funds, "duplicate does not charge")

	for model: SharedWorld in [SharedWorld.new(), RegionWorld.new()]:
		check(model.open(loaded), "open municipal mode")
		check(model.add_player("alice").is_empty(), "add owner")
		check(model.add_player("bob").is_empty(), "add second owner")
		check(ExpandedRules.enabled(model.municipalities["bob"].city.document), "new municipality inherits Expanded")
		var second_funds: int = model.municipalities["bob"].city.funds()
		var own := request.duplicate(true)
		own.revision = model.revision
		if model is RegionWorld:
			own.view_owner = "alice".sha256_text()
		check(not model.command("bob", own).get("ok", false), "foreign building rejected")
		check(model.municipalities["bob"].city.funds() == second_funds, "foreign request costs nothing")
		own.revision = model.revision
		var accepted := model.command("alice", own)
		check(accepted.get("ok", false), "own upgrade in municipal mode: " + str(accepted))
		var snapshot := model.snapshot_for("bob")
		if model is RegionWorld:
			continue
		var display := Sc2File.new()
		check(display.parse(Marshalls.base64_to_raw(snapshot.city)), "shared foreign display loads")
		var viewed := CityState.from_document(display)
		check(viewed.is_valid(), "shared display preserves own identities: " + viewed.load_error)
		check(BuildingUpgrades.budget(viewed).annual == 0, "foreign upkeep excluded")
		check(display.sc2x_metadata.extensions.get("upgrade_view_markers", []).size() == 1, "foreign stars shown")
		var parcel: Rect2i = BuildingUpgrades.info(model.municipalities["alice"].city, point).site
		var cells: Array = []
		for x in range(parcel.position.x, parcel.end.x):
			for y in range(parcel.position.y, parcel.end.y):
				cells.append(x * 64 + y)
		var transferred := SharedLandTransfer.stage(model.municipalities["alice"].city, model.municipalities["bob"].city, cells)
		check(transferred.error.is_empty(), "transfer upgraded parcel")
		if transferred.error.is_empty():
			check(transferred.seller.is_valid() and transferred.buyer.is_valid(), "transfer identity remapping")
			check(BuildingUpgrades.info(transferred.buyer, point).target == 2, "buyer keeps ongoing construction")

	var broken := loaded.duplicate_document()
	broken.sc2x_metadata.required_features.erase(BuildingUpgrades.FEATURE)
	check(not CityState.from_document(broken).is_valid(), "capability is required")
	print("building_upgrades_test: %d failures" % failures)
	quit(0 if failures == 0 else 1)
