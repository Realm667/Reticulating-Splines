class_name MultiplayerLandMarket
extends RefCounted
## Exact parcels and prices always require the other party's consent.
@warning_ignore_start("integer_division")
var windows_ref: WeakRef
var windows: MultiplayerWindows:
	get:
		return windows_ref.get_ref()
var window: Window
var body: VBoxContainer
var entries_box: VBoxContainer
var tabs: MultiplayerTabs
var signature := ""
var known: Dictionary = {}
var initialized := false
var unread := 0
var detail: Window
var notice_label: RichTextLabel
var notification: PanelContainer
var notice_record: Dictionary = {}
var active_record := ""
var map_detail: PanelContainer
var balance_label: Label
var preview_record: Dictionary = {}

func _init(owner: MultiplayerWindows) -> void:
	windows_ref = weakref(owner)

func refresh(state: Dictionary) -> void:
	if is_instance_valid(balance_label) and not preview_record.is_empty():
		balance_label.text = balance_text(preview_record)
	var entries: Array = state.get("offers", []).duplicate(true)
	entries.append_array(state.get("land_history", []))
	var current := TranslationServer.get_locale() + JSON.stringify(entries)
	if current == signature:
		return
	signature = current
	var identity := windows.coop.session.token.sha256_text()
	for record: Dictionary in entries:
		var key := JSON.stringify([record.id, record.status, record.price, record.get("awaiting", "")])
		if initialized and not known.has(key) and (identity in [record.seller, record.buyer] or record.buyer == ""):
			unread += 1
			if record.status == "Open" and (record.get("awaiting") == identity or (record.buyer == "" and record.seller != identity)):
				notify_offer(record)
		known[key] = true
		if known.size() > 512:
			known.erase(known.keys()[0])
		if str(record.id) == active_record and record.status != "Open":
			close_map()
			windows.coop.show_message(tr(record.status))
		if str(record.id) == str(notice_record.get("id", "")) and record.status != "Open" and is_instance_valid(notification):
			notification.hide()
	initialized = true
	var popup := windows.menu.get_popup()
	popup.set_item_text(popup.get_item_index(7), tr("Land trade") + (" · %d" % unread if unread > 0 else ""))
	if is_instance_valid(window) and window.visible:
		rebuild()

func open() -> void:
	if not is_instance_valid(window):
		window = windows.make_window("Land trade")
		window.size.x = 760
		body = windows.content(window)
		tabs = MultiplayerTabs.new()
		body.add_child(tabs)
		for title in ["Inbox", "Outbox", "History"]:
			tabs.add_item(title)
		tabs.item_selected.connect(func(_index: int) -> void: rebuild())
		entries_box = VBoxContainer.new()
		body.add_child(entries_box)
	unread = 0
	windows.menu.get_popup().set_item_text(windows.menu.get_popup().get_item_index(7), tr("Land trade"))
	rebuild()
	window.popup_centered()

func rebuild() -> void:
	for child in entries_box.get_children():
		entries_box.remove_child(child)
		child.queue_free()
	var identity := windows.coop.session.token.sha256_text()
	var entries: Array = windows.state.get("offers", []).duplicate(true)
	entries.append_array(windows.state.get("land_history", []))
	var count := 0
	for record: Dictionary in entries:
		var closed: bool = record.status != "Open"
		var mine: bool = record.get("initiator", record.seller) == identity
		var relevant: bool = identity in [record.seller, record.buyer] or record.buyer == ""
		if not relevant or (tabs.selected == 2) != closed or (not closed and (tabs.selected == 1) != mine):
			continue
		count += 1
		var panel := PanelContainer.new()
		panel.theme = AppUiTheme.current()
		var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.border_width_left = 4
		style.border_color = Color("ffa451") if record.buyer != "" else Color("65c78e")
		style.content_margin_left = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", style)
		entries_box.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var request: bool = record.buyer != "" and record.get("initiator") == record.buyer
		ApplicationMultiplayer.label(box, tr("Release reserved land") if record.get("reservation", false) else "↔ " + tr("Purchase request") if request else "▣ " + tr("Land sale offer"))
		var parties := RichTextLabel.new()
		parties.fit_content = true
		parties.scroll_active = false
		box.add_child(parties)
		for id: String in [record.seller, record.buyer]:
			if id == record.buyer:
				parties.add_text(" → ")
			if id.is_empty():
				parties.add_text(tr("Any player"))
			for player: Dictionary in windows.players:
				if player.id == id:
					parties.push_color(Color(CoopSession.valid_color(player.color)))
					parties.add_text(str(player.name) + " · " + str(player.city) + "  ")
					parties.pop()
		ApplicationMultiplayer.label(box, tr("%d tiles · %s: %s · %s per tile") % [record.count, tr("Payment to game") if record.get("reservation", false) else tr("You receive") if identity == record.seller else tr("You pay"), MultiplayerScoreboard.money(record.price), ("≈ " if int(record.price) % maxi(1, int(record.count)) != 0 else "") + MultiplayerScoreboard.money(int(record.price) / maxi(1, int(record.count)))])
		ApplicationMultiplayer.label(box, "◷ " + ((tr("Your response required") if record.get("awaiting") == identity else tr("Awaiting response")) if not closed else tr(record.status)))
		var actions := HFlowContainer.new()
		box.add_child(actions)
		add_action(actions, tr("Show on map"), func() -> void: show_on_map(record))
		add_action(actions, tr("Review"), func() -> void: review(record))
	if count == 0:
		ApplicationMultiplayer.label(entries_box, "No entries.")
	windows.fit_content.call_deferred(window, body, 760)

func review(record: Dictionary) -> void:
	var box := map_panel(record.tiles, tr("Review land trade"))
	ApplicationMultiplayer.label(box, str(record.name))
	ApplicationMultiplayer.label(box, parcel_counts(record.tiles))
	active_record = str(record.id)
	var identity := windows.coop.session.token.sha256_text()
	var receive: bool = identity == record.seller
	var reserved: bool = record.get("reservation", false)
	ApplicationMultiplayer.label(box, tr("%d tiles · %s: %s") % [record.count, tr("Payment to game") if reserved else tr("You receive") if receive else tr("You pay"), MultiplayerScoreboard.money(record.price)])
	if reserved:
		ApplicationMultiplayer.label(box, "Release only this parcel. The buyer pays the game; you receive no money.")
	preview_record = record.duplicate(true)
	balance_label = ApplicationMultiplayer.label(box, balance_text(record))
	var actions := HFlowContainer.new()
	box.add_child(actions)
	if record.status == "Open":
		var awaiting: String = record.get("awaiting", "")
		if identity == awaiting or (awaiting.is_empty() and identity != record.seller):
			add_action(actions, tr("Approve release") if reserved else tr("Accept"), func() -> void: submit_record("land_accept", record))
			if not reserved:
				add_action(actions, tr("Counteroffer"), func() -> void: counter(record))
			if not str(record.buyer).is_empty():
				add_action(actions, tr("Decline"), func() -> void: submit_record("land_decline", record))
		if identity == record.get("initiator", record.seller):
			if not reserved:
				add_action(actions, tr("Change price"), func() -> void: counter(record))
			add_action(actions, tr("Withdraw"), func() -> void: submit_record("land_withdraw", record))
	add_action(actions, tr("Close"), close_map)

func confirm(record: Dictionary) -> void:
	review(record)

func submit_record(kind: String, record: Dictionary) -> void:
	windows.coop.session.request({"kind": kind, "offer": record.id})
	if is_instance_valid(detail):
		detail.hide()
	close_map()

func counter(record: Dictionary) -> void:
	var dialog := windows.make_window("Counteroffer")
	var box := windows.content(dialog)
	ApplicationMultiplayer.label(box, "Total price · the other player must confirm")
	var price := SpinBox.new()
	price.max_value = 2147483647
	price.value = record.price
	price.prefix = "$"
	box.add_child(price)
	ApplicationMultiplayer.label(box, parcel_counts(record.tiles))
	var balance := ApplicationMultiplayer.label(box, balance_text(record))
	price.value_changed.connect(func(value: float) -> void:
		var proposed := record.duplicate(true)
		proposed.price = int(value)
		balance.text = balance_text(proposed))
	add_action(box, tr("Send counteroffer"), func() -> void:
		windows.coop.session.request({"kind": "land_counter", "offer": record.id, "price": int(price.value)})
		dialog.queue_free()
		close_map())
	dialog.popup_centered()

func show_on_map(record: Dictionary) -> void:
	review(record)

func close_map() -> void:
	active_record = ""
	preview_record.clear()
	windows.map_overlay.highlight.clear()
	if is_instance_valid(map_detail):
		map_detail.queue_free()
		map_detail = null

func map_panel(tiles: Array, title: String) -> VBoxContainer:
	close_map()
	var map := windows.coop.app.map_view
	windows.map_overlay.highlight = tiles.duplicate()
	windows.map_overlay.highlight_until = Time.get_ticks_msec() + 3600000
	windows.coop.app.camera_input.center_map_on_tile(tile_bounds(tiles, map.city.map_size).get_center())
	if is_instance_valid(window):
		window.hide()
	if is_instance_valid(detail):
		detail.hide()
	map_detail = PanelContainer.new()
	map_detail.theme = AppUiTheme.current()
	map_detail.z_index = 3
	map.add_child(map_detail)
	map_detail.position = map.camera_view_rect.position + Vector2(12, 12)
	map_detail.custom_minimum_size.x = minf(360, maxf(0, map.camera_view_rect.size.x - 24))
	var box := VBoxContainer.new()
	map_detail.add_child(box)
	ApplicationMultiplayer.label(box, title)
	return box

func notify_offer(record: Dictionary) -> void:
	notice_record = record.duplicate(true)
	if not is_instance_valid(notification):
		notification = PanelContainer.new()
		notification.theme = AppUiTheme.current()
		notification.z_index = 4
		windows.coop.app.map_view.add_child(notification)
		var row := HBoxContainer.new()
		notification.add_child(row)
		notice_label = RichTextLabel.new()
		notice_label.fit_content = true
		notice_label.custom_minimum_size.x = 260
		notice_label.scroll_active = false
		row.add_child(notice_label)
		add_action(row, tr("View"), func() -> void:
			review(notice_record)
			notification.hide())
		add_action(row, "×", notification.hide)
	notification.position = windows.coop.app.map_view.camera_view_rect.position + Vector2(12, 12)
	notice_label.clear()
	for player: Dictionary in windows.players:
		if player.id == record.get("initiator", record.seller):
			notice_label.push_color(Color(CoopSession.valid_color(player.color)))
			notice_label.add_text(str(player.name) + "\n")
			notice_label.pop()
	notice_label.add_text(tr("Land trade: %d tiles · %s") % [record.count, MultiplayerScoreboard.money(record.price)])
	notice_label.add_text("\n" + tr("Your response required"))
	notification.show()
	windows.play_cue("chat", true)

func select_parcel(start: Vector2i, finish: Vector2i) -> void:
	var state := windows.state
	var owners: Array = state.get("owners", [])
	var ids: Array = state.get("owner_ids", [])
	var city := windows.coop.app.document_state.city
	var groups := {}
	for x in range(maxi(0, mini(start.x, finish.x)), mini(city.map_size - 1, maxi(start.x, finish.x)) + 1):
		for y in range(maxi(0, mini(start.y, finish.y)), mini(city.map_size - 1, maxi(start.y, finish.y)) + 1):
			var tile := city.index_of(x, y)
			if not windows.include_water and city.is_water(x, y):
				continue
			var owner := int(owners[tile])
			var own := ids.find(windows.coop.session.token.sha256_text()) + 1
			if windows.land_action == "land_offer" and owner != own:
				continue
			if windows.land_action != "land_offer" and owner == own:
				continue
			var reserved := int(state.get("protection", [])[tile]) if state.get("protection", []).size() == owners.size() else 0
			if reserved == -1:
				continue
			if owner == 0 and reserved > 0 and reserved != own:
				owner = -reserved
			if not groups.has(owner):
				groups[owner] = []
			groups[owner].append(tile)
	if groups.has(0) and windows.land_action == "land_buy":
		windows.coop.session.request({"kind": "land_buy", "start": [start.x, start.y], "finish": [finish.x, finish.y], "include_water": windows.include_water})
	groups.erase(0)
	if groups.size() == 1:
		var owner: int = groups.keys()[0]
		open_parcel(owner, groups[owner], start, finish)
	elif groups.size() > 1:
		var chooser := windows.make_window("Choose a parcel")
		var box := windows.content(chooser)
		ApplicationMultiplayer.label(box, "This selection contains several owners. Choose one parcel to negotiate.")
		for owner: int in groups:
			var name := ""
			for player: Dictionary in windows.players:
				if player.id == ids[absi(owner) - 1]:
					name = player.name
			add_action(box, tr("%s · %d tiles") % [name + (" · " + tr("Reserved") if owner < 0 else ""), groups[owner].size()], func() -> void:
				open_parcel(owner, groups[owner], start, finish)
				chooser.queue_free())
		chooser.popup_centered()

func open_parcel(owner: int, tiles: Array, start: Vector2i, finish: Vector2i) -> void:
	var own: int = windows.state.owner_ids.find(windows.coop.session.token.sha256_text()) + 1
	if owner != own and MultiplayerLandRules.connected(tiles, windows.state.owners, own, windows.coop.app.document_state.city.map_size).size() != tiles.size():
		windows.coop.show_message("This parcel does not connect to the buyer's city.")
		return
	var name := ""
	for player: Dictionary in windows.players:
		if player.id == windows.state.owner_ids[absi(owner) - 1]:
			name = player.name
	var box := map_panel(tiles, tr("Offer land") if owner == windows.state.owner_ids.find(windows.coop.session.token.sha256_text()) + 1 else tr("Request land"))
	ApplicationMultiplayer.label(box, name + " · " + parcel_counts(tiles))
	ApplicationMultiplayer.label(box, "Payment to game" if owner < 0 else "Total price")
	ApplicationMultiplayer.label(box, "You receive" if owner == own else "You pay")
	var price := SpinBox.new()
	price.max_value = 2147483647
	price.value = tiles.size() * int(windows.state.get("land_price", 0))
	price.prefix = "$"
	price.editable = owner >= 0
	box.add_child(price)
	var proposed := {"seller": windows.coop.session.token.sha256_text() if owner == own else "", "price": int(price.value), "reservation": owner < 0}
	var balance := ApplicationMultiplayer.label(box, balance_text(proposed))
	price.value_changed.connect(func(value: float) -> void:
		proposed.price = int(value)
		balance.text = balance_text(proposed))
	if owner < 0:
		ApplicationMultiplayer.label(box, "The reserving player must approve. Payment goes to the game after approval.")
	add_action(box, tr("Publish offer") if owner == windows.state.owner_ids.find(windows.coop.session.token.sha256_text()) + 1 else tr("Send request"), func() -> void:
		windows.coop.session.request({"kind": "land_offer" if owner == windows.state.owner_ids.find(windows.coop.session.token.sha256_text()) + 1 else "land_request", "start": [start.x, start.y], "finish": [finish.x, finish.y], "tiles": tiles, "price": int(price.value)})
		close_map())
	add_action(box, tr("Cancel"), close_map)


func balance_text(record: Dictionary) -> String:
	var identity := windows.coop.session.token.sha256_text()
	for player: Dictionary in windows.players:
		if player.id != identity:
			continue
		var receive: bool = record.get("seller", "") == identity
		var change := int(record.price) * (0 if receive and record.get("reservation", false) else 1 if receive else -1)
		return tr("Balance after transfer: %s") % MultiplayerScoreboard.money(int(player.funds) + change)
	return tr("Not available")

static func tile_bounds(tiles: Array, size: int) -> Rect2i:
	var result := Rect2i()
	var first := true
	for tile: int in tiles:
		var point := Vector2i(tile / size, tile % size)
		result = Rect2i(point, Vector2i.ONE) if first else result.merge(Rect2i(point, Vector2i.ONE))
		first = false
	return result

static func add_action(parent: Control, title: String, action: Callable) -> void:
	ApplicationMultiplayer.button(parent, title, action)

func parcel_counts(tiles: Array) -> String:
	var city := windows.coop.app.document_state.city
	var water := 0
	for tile: int in tiles:
		water += 1 if city.is_water(tile / city.map_size, tile % city.map_size) else 0
	return tr("%d land · %d water") % [tiles.size() - water, water]
