class_name ApplicationRegions
extends RefCounted
## Local region lifecycle and the common, owner-filtered region overview.

var app: CityApplication
var campaign: RegionCampaign
var pending_edge := 0
var switching := false
var window: QolDialog
var grid: RegionGridView
var mini: VBoxContainer
var mini_grid: RegionGridView
var _navigation_signature: Array = []
var _backdrop_signature: Array = []
var _snapshot_queue: Array[Vector2i] = []
var _snapshot_request := Vector2i(-1, -1)
var _snapshot_command := -1
var _snapshot_started_msec := 0
var _switch_command := -1
var heading: Label
var context_hint: Label
var neighbor_details: Label
var create_button: Button
var return_button: Button
var details: Label
var preview: TextureRect
var buy_button: Button
var open_button: Button
var selected := Vector2i(-1, -1)
var quote := {}
var confirmation: ConfirmationDialog
var last_revision := -1
const LOCAL_OWNER := "local"
const SNAPSHOT_TIMEOUT_MSEC := 15000


func _init(application: CityApplication) -> void:
	app = application


func active() -> bool:
	if app.coop.active():
		return not app.coop.session.latest.get("region_campaign", {}).is_empty()
	return campaign != null


func tip_context() -> Dictionary:
	var result := {"mode": "single", "expansion": campaign != null, "administration": campaign != null,
		"equity_check": campaign != null, "own_cities": campaign.own_count(LOCAL_OWNER) if campaign != null else 1}
	if app.coop.active():
		var state: Dictionary = app.coop.session.latest
		result.mode = state.get("mode", "coop")
		var region: Dictionary = state.get("region_campaign", {})
		result.expansion = not region.is_empty()
		result.administration = result.expansion
		result.equity_check = result.expansion
		result.own_cities = 0 if result.expansion else 1
		for item: Dictionary in region.get("cells", []):
			if item.get("own", false):
				result.own_cities += 1
	return result


func activated(document: Sc2File) -> String:
	if switching or app.coop.active():
		return ""
	if not document.sc2x_extra_entries.has(RegionCampaign.ENTRY):
		campaign = null
		return ""
	var loaded := RegionCampaign.new()
	var error := loaded.restore(document)
	if not error.is_empty():
		return error
	if loaded.multiplayer:
		return "Open this regional save through the multiplayer continuation lobby."
	campaign = loaded
	return ""


func found_region() -> bool:
	if pending_edge == 0 or app.coop.active():
		return false
	var edge := pending_edge
	pending_edge = 0
	var error := Sc2xCheckpoint.save_error(app.simulation_state.speed_controller)
	if not error.is_empty():
		app.interface.show_error(tr(error))
		return false
	var document := app.document_state.current_document.duplicate_document(true)
	Sc2xCheckpoint.capture(app.simulation_state.speed_controller, document.sc2x_metadata)
	var staged := RegionCampaign.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	error = staged.initialize(document, edge, rng.randi(), LOCAL_OWNER)
	if not error.is_empty():
		app.interface.show_error(tr(error))
		return false
	return _activate_staged(staged, staged.active_cells[LOCAL_OWNER], "", false)


func process() -> void:
	_sync_navigation()
	_sync_backdrop()
	if app.coop.active():
		if window != null and window.visible:
			var revision: int = int(app.coop.session.latest.get("revision", -1))
			if revision != last_revision:
				last_revision = revision
				refresh()
		return
	if campaign == null or app.document_state.city == null or app.tool_state.landscape_editor:
		return
	var day := app.document_state.city.age_in_days()
	if day > campaign.current_day:
		campaign.advance(day)
		campaign.collect_funds(LOCAL_OWNER, app.document_state.current_document)
		if window != null and window.visible:
			refresh()


func prepare_save() -> String:
	if campaign == null or app.coop.active():
		return ""
	var error := Sc2xCheckpoint.save_error(app.simulation_state.speed_controller)
	if not error.is_empty():
		return error
	Sc2xCheckpoint.capture(app.simulation_state.speed_controller, app.document_state.current_document.sc2x_metadata)
	return campaign.pack(app.document_state.current_document)


func open_overview() -> void:
	if app.document_state.city == null:
		return
	if window == null:
		_build_window()
	selected = Vector2i(-1, -1)
	quote.clear()
	preview.texture = null
	details.text = tr("Select a city area.")
	refresh()
	window.theme = AppUiTheme.current()
	_popup_fitted(window, Vector2i(620, 620))


func open() -> void:
	open_overview()


func _build_window() -> void:
	window = QolDialog.new()
	window.title = "Region overview"
	window.wrap_controls = false
	window.min_size = Vector2i(300, 300)
	app.add_child(window)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	window.column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var frame := window.column
	window.column = content
	heading = window.label("")
	heading.custom_minimum_size.x = 0
	context_hint = window.label("")
	context_hint.custom_minimum_size.x = 0
	grid = RegionGridView.new()
	grid.custom_minimum_size.y = 230
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.cell_selected.connect(_select)
	window.column.add_child(grid)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size.y = 110
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	window.column.add_child(preview)
	details = window.label("Select a city area.")
	details.custom_minimum_size.x = 0
	window.column.add_child(HSeparator.new())
	neighbor_details = window.label("")
	neighbor_details.custom_minimum_size.x = 0
	var actions := HFlowContainer.new()
	frame.add_child(actions)
	buy_button = window.button(actions, "Buy city area", _confirm_purchase)
	open_button = window.button(actions, "Open city", _open_selected)
	return_button = window.button(actions, "Return to your city", func() -> void:
		app.coop.session.request({"kind": "view_city", "seat": app.coop.session.token.sha256_text()})
		window.hide())
	create_button = window.button(actions, "Create a region", open_conversion)
	window.button(actions, "Close", window.hide)
	window.column = frame
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Buy city area"
	confirmation.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation.get_label().custom_minimum_size = Vector2(240, 0)
	app.add_child(confirmation)
	confirmation.confirmed.connect(_purchase)
	if not app.coop.session.command_resolved.is_connected(_command_resolved):
		app.coop.session.command_resolved.connect(_command_resolved)


func summary() -> Dictionary:
	if app.coop.active():
		if app.coop.session.latest.get("mode") == "region":
			return RegionOverviewModel.multiplayer(app.coop.session.latest, app.coop.session.token.sha256_text())
		return RegionOverviewModel.neighbors(app.document_state.city)
	if campaign == null:
		return RegionOverviewModel.neighbors(app.document_state.city)
	var cells := []
	for id: String in campaign.documents:
		var position := RegionRules.cell(id)
		var city := CityState.from_document(campaign.documents[id])
		cells.append({"cell": [position.x, position.y], "own": true, "name": city.city_name(), "population": city.population()})
	var active_cell := RegionRules.cell(campaign.active_cells[LOCAL_OWNER])
	return {"edge": campaign.edge, "cells": cells, "active": [active_cell.x, active_cell.y],
		"funds": campaign.own_funds(LOCAL_OWNER), "debt": campaign.own_debt(LOCAL_OWNER),
		"administration": (campaign.own_count(LOCAL_OWNER) - 1) * RegionRules.ANNUAL_ADMINISTRATION}


func refresh() -> void:
	var state := summary()
	if state.is_empty():
		window.hide()
		return
	grid.configure(state, app.document_state.city.compass_rotation(), selected)
	heading.visible = active()
	heading.text = tr("Own funds: %s · Debt: %s · Administration: %s/year") % [
		BudgetReport.currency(int(state.get("funds", 0))), BudgetReport.currency(int(state.get("debt", 0))),
		BudgetReport.currency(int(state.get("administration", 0)))]
	var item := _cell_summary(selected, state)
	context_hint.text = tr("Select a city to visit. Other cities are read-only; their dialogs remain private.") if state.get("competitive", false) else ""
	if active():
		context_hint.text += ("\n" if not context_hint.text.is_empty() else "") + tr(RegionBoundary.ERROR)
	context_hint.visible = not context_hint.text.is_empty()
	_refresh_neighbors()
	open_button.visible = active() or state.get("competitive", false)
	open_button.text = tr("Visit city") if not item.get("own", false) else tr("Open city")
	var visiting: bool = app.coop.active() and app.coop.session.latest.get("visiting", false)
	open_button.disabled = not (active() and item.get("own", false) and not visiting or RegionOverviewModel.can_visit(item))
	return_button.visible = visiting
	buy_button.visible = active()
	buy_button.disabled = visiting or quote.is_empty() or not item.is_empty()
	create_button.visible = not active() and not app.coop.active() and app.simulation_state.simulation_engine.scenario == null
	preview.visible = preview.texture != null and (not quote.is_empty() or bool(item.get("own", false)))
	if not item.is_empty() and (not active() or not item.get("own", false)):
		_show_city(item)


func _show_city(item: Dictionary) -> void:
	details.text = str(item.get("name", "")) + "\n" + tr("Population: %d") % int(item.get("population", 0))
	if item.has("region"):
		details.text = tr("Region %d") % int(item.region) + " · " + details.text
	if item.has("player"):
		details.text += "\n" + str(item.player) + " · " + MultiplayerSeatWindow.status(item.status)


func _refresh_neighbors() -> void:
	var city := app.document_state.city
	var data := SimNationWindowControl.snapshot(city)
	if not data.ok:
		neighbor_details.text = ""
		return
	# Keep the original national and city population (including arcologies), and
	# the four named neighbors of the currently viewed city, even while visiting.
	var lines: Array[String] = [data.city_name + " · " + tr("Population: %d") % data.display_population,
		tr(SimNationWindowControl.NATIONAL_POPULATION) % data.national_population, tr("Neighbors")]
	var order := SimNationWindowControl.display_neighbor_indices(city.compass_rotation())
	for index in order.size():
		var neighbor: SimNationWindowControl.Neighbor = data.neighbors[order[index]]
		lines.append(["↖", "↗", "↘", "↙"][index] + " " + CityNeighbors.city_name(city, neighbor.index) + " · " + tr("Population: %d") % neighbor.population)
	neighbor_details.text = "\n".join(lines)


func _sync_navigation() -> void:
	if app.city_workspace == null or app.document_state.city == null:
		return
	if not is_instance_valid(mini):
		mini = VBoxContainer.new()
		var button := Button.new()
		button.text = "Region"
		button.tooltip_text = "Region overview"
		button.clip_text = true
		button.custom_minimum_size.y = 36
		button.pressed.connect(open_overview)
		mini.add_child(button)
		mini_grid = RegionGridView.new()
		mini_grid.compact = true
		mini_grid.custom_minimum_size.y = 110
		mini_grid.cell_selected.connect(open_cell)
		mini.add_child(mini_grid)
		app.city_workspace.attach_region_preview(mini)
		_navigation_signature.clear()
	mini.visible = not app.tool_state.landscape_editor
	var city := app.document_state.city
	var signature := [city.get_instance_id(), city.compass_rotation(), city.age_in_days(),
		app.coop.session.latest.get("revision", -1) if app.coop.active() else campaign.revision if campaign != null else -1,
		hash(app.coop.session.latest.get("roster", [])) if app.coop.active() else 0,
		app.coop.session.latest.get("view_owner", "") if app.coop.active() else ""]
	if signature == _navigation_signature:
		return
	_navigation_signature = signature
	var state := summary()
	mini_grid.configure(state, city.compass_rotation())
	if window != null and window.visible and not state.is_empty():
		refresh()


func open_cell(position: Vector2i) -> void:
	var state := summary()
	var item := _cell_summary(position, state)
	if state.get("competitive", false) and (not active() or not item.get("own", false) or app.coop.session.latest.get("visiting", false)):
		if RegionOverviewModel.can_visit(item):
			app.coop.session.request({"kind": "view_city", "seat": item.owner})
		else:
			open_overview()
			_select(position)
		return
	if not active():
		open_overview()
		_select(position)
		return
	if switching or app.map_view.region_backdrop.busy() or not _cell_summary(position, state).get("own", false) or state.get("active") == [position.x, position.y]:
		return
	var backdrop := app.map_view.region_backdrop
	var target: Sc2File = backdrop.documents.get(RegionRules.key(position))
	var compass := int(target.misc_u32(Sc2MiscLayout.COMPASS) & 3) if target != null else app.document_state.city.compass_rotation()
	if backdrop.begin_switch(position, app.document_state.current_document, compass, _perform_open_cell):
		return
	_perform_open_cell(position)


func _perform_open_cell(position: Vector2i) -> void:
	if not is_instance_valid(app):
		return
	if not _cell_summary(position, summary()).get("own", false):
		app.map_view.region_backdrop.cancel_switch()
		return
	if app.coop.active():
		_switch_command = app.coop.session.next_command
		app.coop.session.request({"kind": "region_switch", "cell": [position.x, position.y]})
	else:
		if not _switch_local(RegionRules.key(position)):
			app.map_view.region_backdrop.cancel_switch()


func _sync_backdrop() -> void:
	if app.map_view == null:
		return
	var backdrop := app.map_view.region_backdrop
	if not active() or app.document_state.city == null or app.tool_state.landscape_editor or app.coop.session.latest.get("visiting", false):
		if not backdrop.state.is_empty():
			backdrop.clear()
		_backdrop_signature.clear()
		_snapshot_queue.clear()
		_release_snapshot_request()
		return
	var city := app.document_state.city
	# Inspect only small identities here. Reconstructing every inactive CityState
	# each render frame would scale with the entire region's terrain size.
	var region: Dictionary = app.coop.session.latest.get("region_campaign", {})
	var identity: Variant = [app.coop.session.token, region.get("active", []),
		region.get("cells", []).map(func(entry: Dictionary) -> Array: return [entry.cell, entry.get("own", false)])] if app.coop.active() else [
		campaign.get_instance_id(), campaign.active_cells.get(LOCAL_OWNER, ""), campaign.documents.keys()]
	var signature := [identity, city.compass_rotation(),
		app.asset_state.large_sprites.get_instance_id() if app.asset_state.large_sprites != null else 0,
		app.asset_state.large_sprites.visual_revision if app.asset_state.large_sprites != null else 0,
		app.preferences.visual_enhancements.hash()]
	if signature != _backdrop_signature:
		_backdrop_signature = signature
		var state := summary()
		backdrop.requested = open_cell
		backdrop.live_ready = func() -> bool: return app.visual_preparation.ready
		backdrop.presentation_state = func() -> Dictionary: return {"options": app.preferences.visual_enhancements, "atmosphere": app.visual_environment.network_snapshot()}
		var documents: Dictionary[String, Sc2File] = {}
		if campaign != null and not app.coop.active():
			documents = campaign.documents
		backdrop.configure(state, documents, app.asset_state, city.compass_rotation())
		_snapshot_queue.clear()
		_release_snapshot_request()
		if app.coop.active():
			if not app.coop.session.command_resolved.is_connected(_command_resolved):
				app.coop.session.command_resolved.connect(_command_resolved)
			for entry: Dictionary in state.get("cells", []):
				if entry.get("own", false) and entry.cell != state.get("active"):
					_snapshot_queue.append(Vector2i(entry.cell[0], entry.cell[1]))
			var active_cell: Array = state.get("active", [0, 0])
			CityRegionBackdrop.prioritize(_snapshot_queue, Vector2i(active_cell[0], active_cell[1]))
	_expire_snapshot_request(Time.get_ticks_msec())
	if app.coop.active() and app.coop.session.connected and _snapshot_request.x < 0 and not _snapshot_queue.is_empty():
		_snapshot_request = _snapshot_queue.pop_front()
		_snapshot_command = app.coop.session.next_command
		_snapshot_started_msec = Time.get_ticks_msec()
		app.coop.session.request({"kind": "region_snapshot", "cell": [_snapshot_request.x, _snapshot_request.y]})
	backdrop.poll()


func _release_snapshot_request() -> void:
	_snapshot_request = Vector2i(-1, -1)
	_snapshot_command = -1
	_snapshot_started_msec = 0


func _expire_snapshot_request(now_msec: int) -> void:
	if _snapshot_command >= 0 and now_msec - _snapshot_started_msec >= SNAPSHOT_TIMEOUT_MSEC:
		_release_snapshot_request()


static func _cell_summary(position: Vector2i, state: Dictionary) -> Dictionary:
	for item: Dictionary in state.get("cells", []):
		if item.get("cell") == [position.x, position.y]:
			return item
	return {}


func _select(position: Vector2i) -> void:
	selected = position
	quote.clear()
	preview.texture = null
	var state := summary()
	var item := _cell_summary(position, state)
	if not item.is_empty():
		_show_city(item)
		if active() and item.get("own", false):
			if app.coop.active():
				app.coop.session.request({"kind": "region_offer", "cell": [position.x, position.y]})
			else:
				var document: Sc2File = campaign.documents[RegionRules.key(position)]
				var city := CityState.from_document(document)
				var budget := BudgetReport.capture(city, BudgetPhase.funding_values(city))
				var administration := RegionCampaign.administration_report(document)
				preview.texture = ImageTexture.create_from_image(terrain_preview(document))
				_show_owned_city(item, budget.estimated_cash - int(administration.estimated))
		refresh()
		return
	if not active():
		details.text = tr("Select a city area.")
		refresh()
		return
	if app.coop.active():
		app.coop.session.request({"kind": "region_offer", "cell": [position.x, position.y]})
	else:
		if not campaign.adjacent(LOCAL_OWNER, position):
			details.text = tr("Choose an available city area next to your own territory.")
			refresh()
			return
		var result := campaign.offer(position)
		if not result.ok:
			details.text = tr(result.error)
		else:
			quote = result
			quote["cell"] = [position.x, position.y]
			quote["quote_revision"] = campaign.revision
			preview.texture = ImageTexture.create_from_image(terrain_preview(result.document))
			_show_quote()
			app.knowledge.region_tip("mp_landscape")
	refresh()


static func terrain_preview(document: Sc2File) -> Image:
	var size := document.map_size
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var terrain := document.find_chunk("XTER").decoded_payload
	var flags := document.find_chunk("XBIT").decoded_payload
	for x in size:
		for y in size:
			var index := x * size + y
			image.set_pixel(x, y, Color("397ab4") if flags[index] & Sc2TileFlags.WATER else
				Color("9b8c63") if terrain[index] & TerrainTileIds.SHAPE_MASK else Color("78954f"))
	return image


func _show_quote() -> void:
	details.text = tr("Purchase: %s · Additional administration: %s/year\nFlat land: %d · Slopes: %d · Water: %d") % [
		BudgetReport.currency(int(quote.price)), BudgetReport.currency(RegionRules.ANNUAL_ADMINISTRATION),
		int(quote.flat), int(quote.slope), int(quote.water)]
	var state := summary()
	details.text += "\n" + tr("Annual administration after purchase: %s\nFunds after purchase: %s") % [
		BudgetReport.currency(int(state.get("administration", 0)) + RegionRules.ANNUAL_ADMINISTRATION),
		BudgetReport.currency(int(state.get("funds", 0)) - int(quote.price))]


func _show_owned_city(item: Dictionary, annual_balance: int) -> void:
	_show_city(_cell_summary(selected, summary()).merged(item, true))
	details.text += "\n" + tr("Projected annual balance: %s") % BudgetReport.currency(annual_balance)


func _confirm_purchase() -> void:
	if quote.is_empty():
		return
	_show_quote()
	confirmation.dialog_text = details.text + "\n" + tr("Keep one year of administration costs in reserve. Borrowed funds do not increase your purchasing power.")
	confirmation.theme = AppUiTheme.current()
	_popup_fitted(confirmation, Vector2i(540, 260))


func _purchase() -> void:
	if quote.get("cell") != [selected.x, selected.y]:
		return
	if app.coop.active():
		app.coop.session.request({"kind": "region_buy", "cell": [selected.x, selected.y], "quote_revision": quote.quote_revision})
		return
	var error := prepare_save()
	if not error.is_empty():
		app.interface.show_error(tr(error))
		return
	# Stage the complete transaction, including cash and archive, before publishing it.
	var staged := RegionCampaign.new()
	error = staged.restore(app.document_state.current_document.duplicate_document(true))
	if not error.is_empty():
		app.interface.show_error(tr(error))
		return
	var result := staged.purchase(LOCAL_OWNER, selected, staged.current_day)
	if not result.ok:
		app.interface.show_error(tr(result.error))
		app.knowledge.region_tip("mp_equity")
		return
	var path: String = app.document_state.current_save_path
	if not _activate_staged(staged, RegionRules.key(selected), path, not path.is_empty()):
		return
	quote.clear()
	_select(selected)
	app.knowledge.region_tip("mp_administration")
	app.city_files.open_rename_dialog()


func _open_selected() -> void:
	open_cell(selected)
	window.hide()


func _switch_local(id: String) -> bool:
	if campaign == null or not campaign.documents.has(id) or campaign.owners[id] != LOCAL_OWNER:
		return false
	# Pack the live document first so edits since the previous save are included.
	var error := prepare_save()
	if not error.is_empty():
		app.interface.show_error(tr(error))
		return false
	var staged := RegionCampaign.new()
	error = staged.restore(app.document_state.current_document.duplicate_document(true))
	if not error.is_empty():
		app.interface.show_error(tr(error))
		return false
	return _activate_staged(staged, id, app.document_state.current_save_path, false)


static func prepare_activation(staged: RegionCampaign, id: String, path: String) -> Dictionary:
	if not staged.documents.has(id) or staged.owners.get(id) != LOCAL_OWNER:
		return RegionCampaign.failure("This city area does not belong to you.")
	var document: Sc2File = staged.documents[id]
	var model := CityState.from_document(document)
	if not model.is_valid():
		return RegionCampaign.failure(model.load_error)
	if not staged.collect_funds(LOCAL_OWNER, document):
		return RegionCampaign.failure("The regional treasury exceeds the supported balance.")
	staged.active_cells[LOCAL_OWNER] = id
	document.source_path = path
	var error := staged.pack(document)
	if not error.is_empty():
		return RegionCampaign.failure(error)
	var verified := RegionCampaign.new()
	error = verified.restore(document.duplicate_document(true))
	if not error.is_empty():
		return RegionCampaign.failure(error)
	return {"ok": true, "error": "", "document": document}


func _activate_staged(staged: RegionCampaign, id: String, path: String, write: bool) -> bool:
	# Callers own an isolated campaign. A rejected pack/write never touches live money.
	var result := prepare_activation(staged, id, path)
	if not result.ok:
		app.interface.show_error(tr(result.error))
		return false
	var document: Sc2File = result.document
	if write:
		var prepared := CityFileStore.prepare(document, path, app.asset_state.reference_root)
		prepared.backup_previous = true
		if not prepared.ok:
			app.interface.show_error(tr(prepared.error))
			return false
		var written := CityFileStore.write(prepared)
		if not written.ok:
			app.interface.show_error(tr(written.error))
			return false
	# Activation has two rejection points: model validation (above), then regions.
	# Switching bypasses only the latter; publish the staged context for UI callbacks.
	var previous := campaign
	campaign = staged
	switching = true
	var activated_ok := app.city_session.activate_document(document, null, "", true)
	switching = false
	if not activated_ok:
		campaign = previous
		return false
	app.document_state.current_save_path = path
	app.document_state.saved_city_snapshot = PackedByteArray()
	app.simulation_state.simulation_engine.clock.city_days = campaign.current_day
	app.frame.select_speed(GameSpeedController.Speed.PAUSED)
	app.interface.refresh_details()
	return true


func _command_resolved(command_id: int, result: Dictionary) -> void:
	if command_id == _switch_command and _switch_command >= 0:
		_switch_command = -1
		if not result.get("ok", false):
			app.map_view.region_backdrop.cancel_switch()
		return
	if command_id == _snapshot_command and _snapshot_command >= 0:
		var position := _snapshot_request
		_release_snapshot_request()
		# Rejection or malformed replies must release the queue as well. A late
		# result from a previous view cannot replace a newer city's snapshot.
		if not result.get("ok", false) or not result.get("region_snapshot") is Dictionary:
			return
		var snapshot: Dictionary = result.region_snapshot
		if snapshot.get("cell") != [position.x, position.y] or not app.coop.active():
			return
		if _cell_summary(position, summary()).get("own", false):
			var document := Sc2File.new()
			if document.parse(Marshalls.base64_to_raw(str(snapshot.get("document", "")))) and document.is_sc2x():
				app.map_view.region_backdrop.add_document(position, document)
		return
	if result.has("region_snapshot"):
		return
	if window == null or not window.visible:
		return
	if result.has("region_city"):
		var item: Dictionary = result.region_city
		if item.get("cell") != [selected.x, selected.y] or not item.get("own", false):
			return
		if not _cell_summary(selected, summary()).get("own", false):
			return
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(str(item.get("preview", "")))) == OK:
			preview.texture = ImageTexture.create_from_image(image)
		_show_owned_city(item, int(item.get("budget", {}).get("projected_cash", 0)))
	if result.has("region_offer"):
		var offered: Dictionary = result.region_offer
		if offered.get("cell") != [selected.x, selected.y]:
			return
		quote = offered
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(str(offered.get("preview", "")))) == OK:
			preview.texture = ImageTexture.create_from_image(image)
		_show_quote()
	refresh()


func open_conversion() -> void:
	if app.coop.active() or app.document_state.city == null or app.simulation_state.simulation_engine.scenario != null:
		return
	var dialog := QolDialog.new()
	dialog.title = "Create a region"
	dialog.wrap_controls = false
	dialog.label("Turn this city into the first city of a new region. A separate backup is saved first. No additional starting funds are granted.").custom_minimum_size.x = 0
	dialog.label("Region size").custom_minimum_size.x = 0
	var sizes := OptionButton.new()
	for value in RegionRules.SIZES:
		sizes.add_item("%d × %d" % [value, value], value)
	sizes.select(1)
	dialog.column.add_child(sizes)
	app.add_child(dialog)
	var actions := HFlowContainer.new()
	dialog.column.add_child(actions)
	dialog.button(actions, "Create a region", func() -> void:
		if _convert_local(sizes.get_selected_id()):
			dialog.queue_free()
			open_overview())
	dialog.button(actions, "Cancel", dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	_popup_fitted(dialog, Vector2i(520, 300))


static func conversion_document(source: Sc2File) -> Dictionary:
	if source == null or not source.is_valid():
		return RegionCampaign.failure("No city is loaded.")
	if source.is_sc2x():
		return {"ok": true, "error": "", "document": source.duplicate_document(true)}
	var converted := Sc2xDocument.from_legacy(source)
	return {"ok": converted.ok, "error": converted.error, "document": converted.document}


func _convert_local(edge: int) -> bool:
	if active() or app.coop.active() or app.document_state.city == null:
		return false
	var error := Sc2xCheckpoint.save_error(app.simulation_state.speed_controller)
	if not error.is_empty():
		app.interface.show_error(tr(error))
		return false
	var result := conversion_document(app.document_state.current_document)
	if not result.ok:
		app.interface.show_error(tr(result.error))
		return false
	var document: Sc2File = result.document
	Sc2xCheckpoint.capture(app.simulation_state.speed_controller, document.sc2x_metadata)
	var staged := RegionCampaign.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# The backup remains a single city; initialization changes only the second copy.
	error = staged.initialize(document.duplicate_document(true), edge, rng.randi(), LOCAL_OWNER)
	if not error.is_empty():
		app.interface.show_error(tr(error))
		return false
	var checked := prepare_activation(staged, staged.active_cells[LOCAL_OWNER], "")
	if not checked.ok:
		app.interface.show_error(tr(checked.error))
		return false
	var backup_path := AppPaths.path("cities").path_join(document.city_name().validate_filename() + "-before-region-" + str(Time.get_unix_time_from_system()).replace(".", "-") + ".sc2x")
	var backup := CityFileStore.save_copy(document, backup_path, app.asset_state.reference_root)
	if not backup.ok:
		app.interface.show_error(tr(backup.error))
		return false
	return _activate_staged(staged, staged.active_cells[LOCAL_OWNER], "", false)


func _popup_fitted(dialog: Window, preferred: Vector2i) -> void:
	var available := (Vector2i(app.get_viewport_rect().size) - Vector2i(24, 48)).max(Vector2i(1, 1))
	dialog.min_size = Vector2i(240, 180).min(available)
	dialog.max_size = available
	dialog.popup_centered(preferred.min(available))
