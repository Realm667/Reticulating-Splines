class_name MultiplayerLanBrowser
extends VBoxContainer
## Search results are hints only. The regular TCP handshake still decides admission.

var owner_ref: WeakRef
var coop: ApplicationMultiplayer:
	get:
		return owner_ref.get_ref()
var discovery := MultiplayerLanDiscovery.new()
var search_button: Button
var status: Label
var games: Tree
var last_error := false
var searched := false


func setup(owner: ApplicationMultiplayer) -> void:
	owner_ref = weakref(owner)
	add_child(discovery)
	search_button = ApplicationMultiplayer.button(self, "Search LAN games", start_search)
	search_button.tooltip_text = "Find lobbies and running games on the local IPv4 network. Select a game, then join."
	status = ApplicationMultiplayer.label(self, "")
	games = Tree.new()
	games.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	games.columns = 3
	games.hide_root = true
	games.column_titles_visible = true
	games.select_mode = Tree.SELECT_ROW
	games.custom_minimum_size.y = 135
	games.set_column_expand_ratio(0, 3)
	games.set_column_expand_ratio(1, 2)
	games.set_column_expand_ratio(2, 2)
	for column in 3:
		games.set_column_clip_content(column, true)
	add_child(games)
	games.item_selected.connect(select_game)
	discovery.results_changed.connect(refresh)
	discovery.search_finished.connect(refresh)
	coop.panel.visibility_changed.connect(sync_visibility)
	coop.session.connection_changed.connect(sync_visibility)
	refresh()


func sync_visibility() -> void:
	if not visible or not coop.panel.visible or coop.session.active:
		discovery.cancel_search(true)
		searched = false
		last_error = false
		refresh()


func start_search() -> void:
	if coop.session.active:
		return
	searched = true
	last_error = discovery.search() != OK
	refresh()


func refresh() -> void:
	if games == null:
		return
	search_button.disabled = discovery.searching
	if last_error:
		status.text = tr("LAN search unavailable. You can still enter the host address.")
	elif discovery.searching:
		status.text = tr("Searching the local network…")
	elif discovery.results.is_empty() and searched:
		status.text = tr("No games found. Search again, or enter the host address. Check the host's firewall and LAN connection.")
	else:
		status.text = tr("Select a game to fill in its address and port. Passwords are entered below.")
	var selected_key := ""
	if games.get_selected() != null:
		selected_key = str(games.get_selected().get_metadata(0))
	games.clear()
	var root := games.create_item()
	for column in 3:
		games.set_column_title(column, tr(["City / Host", "Game mode", "Status / Players"][column]))
	for key: String in discovery.results:
		var info: Dictionary = discovery.results[key]
		var item := games.create_item(root)
		item.set_metadata(0, key)
		item.set_text(0, info.city + " · " + info.host)
		item.set_text(1, tr({"coop": "Co-op", "shared": "Competitive Shared", "region": "Competitive Region"}[info.mode]))
		var phase := tr("Lobby") if info.phase == "lobby" else tr("In progress")
		if not info.open:
			phase = tr("Full")
		if info.build != CoopSession.NETWORK_BUILD:
			phase = tr("Different game version")
		item.set_text(2, "%s · %d/8%s" % [phase, info.players, " · " + tr("Password") if info.locked else ""])
		var usable: bool = info.open and info.build == CoopSession.NETWORK_BUILD
		for column in 3:
			item.set_selectable(column, usable)
			item.set_tooltip_text(column, "%s\n%s\n%s:%d\n%s" % [item.get_text(0), item.get_text(2), info.address, info.port, info.build])
			if not usable:
				item.set_custom_color(column, Color(0.6, 0.6, 0.6))
		if usable and key == selected_key:
			item.select(0)
	coop.launch.fit.call_deferred()


func select_game() -> void:
	var item := games.get_selected()
	if item == null:
		return
	var info: Dictionary = discovery.results.get(str(item.get_metadata(0)), {})
	if info.is_empty() or not info.open or info.build != CoopSession.NETWORK_BUILD:
		return
	var changed: bool = coop.address.text != info.address or int(coop.port.value) != info.port
	coop.address.text = info.address
	coop.port.value = info.port
	if changed:
		coop.join_code.clear()
