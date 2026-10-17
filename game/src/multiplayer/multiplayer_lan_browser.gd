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
var internet := false
var request: HTTPRequest
var pending := false
var refresh_at := 0
var selected_online := ""
var lock_icon: Texture2D


func setup(owner: ApplicationMultiplayer, use_internet := false) -> void:
	owner_ref = weakref(owner)
	internet = use_internet
	add_child(discovery)
	var lock_image := Image.new()
	lock_image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="16"><path d="M4 7V5a3 3 0 0 1 6 0v2" fill="none" stroke="#ccc" stroke-width="2"/><rect x="2" y="7" width="10" height="8" rx="1" fill="#ccc"/><path d="M7 10v3" stroke="#333" stroke-width="2"/></svg>')
	lock_icon = ImageTexture.create_from_image(lock_image)
	search_button = ApplicationMultiplayer.button(self, "Find Internet games" if internet else "Search LAN games", start_search)
	search_button.tooltip_text = "Find lobbies and running games on the local IPv4 network. Select a game, then join."
	if internet:
		search_button.tooltip_text = "Find online lobbies and running games. Password-protected games show a lock."
		request = HTTPRequest.new()
		request.use_threads = true
		request.timeout = 8
		request.body_size_limit = 256 * 1024
		request.max_redirects = 0
		add_child(request)
		request.request_completed.connect(receive_games)
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
		if request != null:
			request.cancel_request()
		pending = false
		selected_online = ""
		discovery.cancel_search(true)
		searched = false
		last_error = false
		refresh()


func start_search() -> void:
	if coop.session.active:
		return
	searched = true
	if internet:
		pending = true
		last_error = request.request(MultiplayerOnline.base_url() + MultiplayerOnline.API + "/games") != OK
		if last_error:
			pending = false
		refresh_at = Time.get_ticks_msec() + 60000
	else:
		last_error = discovery.search() != OK
	refresh()


func _process(_delta: float) -> void:
	if internet and is_visible_in_tree() and coop.panel.visible and not coop.session.active and searched and not pending and Time.get_ticks_msec() >= refresh_at:
		start_search()


func receive_games(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	pending = false
	discovery.results.clear()
	last_error = result != HTTPRequest.RESULT_SUCCESS or response_code != 200
	var parser := JSON.new()
	if not last_error:
		last_error = parser.parse(body.get_string_from_utf8()) != OK or not parser.data is Dictionary
	if not last_error:
		var data: Dictionary = parser.data
		last_error = not data.get("version") is float and not data.get("version") is int
		if not last_error:
			last_error = data.version != 2 or not data.get("games") is Array or data.games.size() > 256
		if not last_error:
			for item: Variant in data.games:
				var info := validated_game(item)
				if not info.is_empty():
					discovery.results[info.id] = info
	if not discovery.results.has(selected_online):
		selected_online = ""
	refresh()


static func validated_game(value: Variant) -> Dictionary:
	if not value is Dictionary or not MultiplayerLanDiscovery.valid_nonce(value.get("id")):
		return {}
	for key in ["city", "host", "build", "mode", "phase"]:
		if not value.get(key) is String or value[key].length() > 64:
			return {}
	if not value.mode in ["coop", "shared", "region"] or not value.phase in ["lobby", "running"]:
		return {}
	if not MultiplayerLanDiscovery.valid_integer(value.get("players"), 1, 8) or not value.get("locked") is bool or not value.get("open") is bool:
		return {}
	if not value.get("address") is String or not value.address.is_valid_ip_address() or not MultiplayerLanDiscovery.valid_integer(value.get("port"), 1024, 65535):
		return {}
	var info: Dictionary = value.duplicate()
	info.city = MultiplayerLanDiscovery.plain_name(info.city)
	info.host = MultiplayerLanDiscovery.plain_name(info.host)
	return info


func refresh() -> void:
	if games == null:
		return
	search_button.disabled = discovery.searching or pending
	if last_error:
		status.text = tr("Internet games unavailable. Use a direct connection or LAN search.") if internet else tr("LAN search unavailable. You can still enter the host address.")
	elif pending:
		status.text = tr("Finding Internet games…")
	elif discovery.searching:
		status.text = tr("Searching the local network…")
	elif discovery.results.is_empty() and searched:
		status.text = tr("No public games right now.") if internet else tr("No games found. Search again, or enter the host address. Check the host's firewall and LAN connection.")
	else:
		status.text = tr("Select a game, enter its password if needed, then join.") if internet else tr("Select a game to fill in its address and port. Passwords are entered below.")
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
		if info.locked:
			item.set_icon(0, lock_icon)
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
			item.set_tooltip_text(column, "%s\n%s\n%s" % [item.get_text(0), item.get_text(2), info.build] if internet else "%s\n%s\n%s:%d\n%s" % [item.get_text(0), item.get_text(2), info.address, info.port, info.build])
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
	if internet:
		if selected_online != info.id:
			coop.join_code.clear()
		selected_online = info.id
	var changed: bool = coop.address.text != info.address or int(coop.port.value) != info.port
	coop.address.text = info.address
	coop.port.value = info.port
	if changed:
		coop.join_code.clear()
