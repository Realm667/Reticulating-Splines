extends SceneTree
## UI entry points and accounting through the existing monthly budget settlement.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.gui_embed_subwindows = true
	await _new_city_fields()
	await _administration_budget()
	_staged_conversion_and_switch()
	print("PASS region UI: game type, compatibility, grid sizes, administration settlement, reload and budget visibility")
	quit()


func _new_city_fields() -> void:
	var dialog := preload("res://src/ui/startup/new_city_terrain_dialog.tscn").instantiate() as NewCityTerrainDialog
	root.add_child(dialog)
	await process_frame
	assert(dialog.region_edge() == 0)
	assert(not dialog.region_size_input.visible and dialog.compatibility_input.visible)
	assert(dialog.game_type_input.get_index() < dialog.city_name_input.get_parent().get_index())
	dialog.compatibility_input.button_pressed = true
	dialog.game_type_input.select(1)
	dialog.game_type_input.item_selected.emit(1)
	assert(not dialog.compatibility_input.visible and not dialog.compatibility_input.button_pressed)
	assert(dialog.region_size_input.visible and dialog.terrain_options().native_maps)
	for index in 3:
		dialog.region_size_input.select(index)
		assert(dialog.region_edge() == index + 2)
	dialog.reset_fields("Region test")
	assert(dialog.region_edge() == 0 and dialog.compatibility_input.visible)
	dialog.queue_free()
	await process_frame


func _staged_conversion_and_switch() -> void:
	var first := Sc2xDocument.create_empty(128, "First").document
	first.set_misc_i32(Sc2MiscLayout.FUNDS, 40000)
	var converted := ApplicationRegions.conversion_document(first)
	assert(converted.ok and converted.document != first, "Existing SC2X cities can enter a region")
	converted.document.set_misc_i32(Sc2MiscLayout.FUNDS, 1)
	assert(first.misc_i32(Sc2MiscLayout.FUNDS) == 40000, "Conversion preparation is isolated")
	assert(ApplicationRegions.conversion_document(EmptyCityTemplate.create()).ok, "Legacy single cities remain convertible")
	var region := RegionCampaign.new()
	assert(region.initialize_at(first, 2, 81, "local", Vector2i.ZERO).is_empty())
	var second := Sc2xDocument.create_empty(128, "Second").document
	second.set_misc_i32(Sc2MiscLayout.FUNDS, 2000)
	region.documents["1,0"] = second
	region.owners["1,0"] = "local"
	region.acquired["1,0"] = 0
	region.settled["1,0"] = 0
	assert(region.pack(first).is_empty())
	# A live edit after an earlier archive must remain in the city being left.
	first.set_misc_i32(Sc2MiscLayout.FUNDS, 39000)
	var staged := RegionCampaign.new()
	assert(staged.restore(first.duplicate_document(true)).is_empty())
	var result := ApplicationRegions.prepare_activation(staged, "1,0", "user://region-test.sc2x")
	assert(result.ok and result.document.misc_i32(Sc2MiscLayout.FUNDS) == 41000)
	assert(result.document.source_path == "user://region-test.sc2x")
	assert(region.active_cells.local == "0,0" and first.misc_i32(Sc2MiscLayout.FUNDS) == 39000)
	assert(second.misc_i32(Sc2MiscLayout.FUNDS) == 2000, "Preparing a switch cannot move live money")
	var restored := RegionCampaign.new()
	assert(restored.restore(result.document.duplicate_document(true)).is_empty())
	assert(restored.active_cells.local == "1,0" and restored.own_funds("local") == 41000)
	var rejected := RegionCampaign.new()
	assert(rejected.restore(first.duplicate_document(true)).is_empty())
	rejected.documents["0,0"].set_misc_i32(Sc2MiscLayout.FUNDS, 2147483647)
	var old_cell := rejected.active_cells.local
	assert(not ApplicationRegions.prepare_activation(rejected, "1,0", "").ok)
	assert(rejected.active_cells.local == old_cell, "Treasury overflow cannot publish a different active city")
	assert(not ApplicationRegions.prepare_activation(rejected, "9,9", "").ok)


func _administration_budget() -> void:
	var primary := Sc2xDocument.create_empty(128, "Primary").document
	primary.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 150)
	primary.set_misc_i32(Sc2MiscLayout.FUNDS, 50000)
	var secondary := Sc2xDocument.create_empty(128, "Secondary").document
	secondary.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 150)
	secondary.set_misc_i32(Sc2MiscLayout.FUNDS, 50000)
	var region := RegionCampaign.new()
	assert(region.initialize_at(primary, 2, 71, "local", Vector2i.ZERO).is_empty())
	region.documents["1,0"] = secondary
	region.owners["1,0"] = "local"
	region.acquired["1,0"] = 150
	region.settled["1,0"] = 150
	region.update_administration("1,0", 150)
	var baseline := CityState.from_document(secondary.duplicate_document(true))
	baseline.document.sc2x_extra_entries.erase(RegionCampaign.ADMIN_ENTRY)
	var random := SimRandom.new(secondary.sc2x_metadata.process_random)
	for day in range(175, 276, 25):
		baseline.set_age_in_days(day)
		assert(BudgetPhase.run(baseline, random, true).ok)
		# The application advances the active city before settling the region.
		primary.set_misc_u32(Sc2MiscLayout.CITY_DAYS, day)
		region.advance(day)
		assert(secondary.misc_i32(Sc2MiscLayout.FUNDS) == baseline.funds() - (day - 150) * 4,
			"Inactive ordinary budgets and daily administration must each settle exactly once")
	assert(secondary.misc_u32(Sc2MiscLayout.YEAR_END) == 1, "The native budget marks year end during December")
	var report := RegionCampaign.administration_report(secondary)
	assert(report.ytd == 500 and report.remaining == 100,
		"December retains the last month's unpaid administration costs")
	var dialog := preload("res://src/ui/city_windows/budget_dialog.tscn").instantiate() as BudgetDialog
	root.add_child(dialog)
	dialog.set_city(CityState.from_document(secondary))
	dialog.open_budget(BudgetPhase.funding_values(dialog.city), false, true)
	await process_frame
	assert(dialog.administration_nodes[0].visible)
	assert((dialog.administration_nodes[2] as Label).text == BudgetReport.currency(-500))
	assert(dialog.total_labels[3].text == BudgetReport.currency(dialog.city.funds() + dialog.report.ytd_cash - 100),
		"Forecast deducts only the remaining fee, not already paid administration")
	dialog.hide()
	assert(region.pack(primary).is_empty())
	var restored := RegionCampaign.new()
	assert(restored.restore(primary.duplicate_document(true)).is_empty())
	for day in [300, 325]:
		baseline.set_age_in_days(day)
		assert(BudgetPhase.run(baseline, random, true).ok)
		primary.set_misc_u32(Sc2MiscLayout.CITY_DAYS, day)
		restored.documents[restored.active_cells.local].set_misc_u32(Sc2MiscLayout.CITY_DAYS, day)
		region.advance(day)
		restored.advance(day)
		assert(secondary.misc_i32(Sc2MiscLayout.FUNDS) == baseline.funds() - (day - 150) * 4)
		assert(restored.own_funds("local") == region.own_funds("local"), "Reloading preserves settlement dates")
		var before := region.own_funds("local")
		region.advance(day)
		assert(region.own_funds("local") == before, "Repeated processing cannot charge fees twice")
		if day == 300:
			assert(RegionCampaign.administration_report(secondary).ytd == 0)
	dialog.set_city(CityState.from_document(primary))
	dialog.open_budget(BudgetPhase.funding_values(dialog.city), false, true)
	assert(not dialog.administration_nodes[0].visible, "The first city has no administration charge")
	dialog.queue_free()
	await process_frame
