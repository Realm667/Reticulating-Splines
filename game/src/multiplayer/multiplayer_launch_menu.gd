class_name MultiplayerLaunchMenu
extends RefCounted

var owner_ref: WeakRef
var coop: ApplicationMultiplayer:
	get:
		return owner_ref.get_ref()
var role: OptionButton
var host_fields: VBoxContainer
var address_box: VBoxContainer
var password_label: Label
var action: Button
var shared_fields: VBoxContainer
var land_price: SpinBox
var goal_fields: VBoxContainer
var goal_picker: OptionButton
var goal_target: SpinBox
var goal_years: OptionButton
var years_label: Label
var duration: SpinBox
var duration_label: Label
var lan_browser: MultiplayerLanBrowser
var internet_browser: MultiplayerLanBrowser
var join_tabs: TabBar
var auto_forward: CheckBox
var lan_only: CheckBox
var visibility_hint: Label
var forwarding_hint: Label
var advanced: CheckButton
var network: HBoxContainer
var compatibility: MultiplayerCompatibility
var compatibility_status: Label

func _init(owner: ApplicationMultiplayer) -> void:
	owner_ref = weakref(owner)

func setup(body: VBoxContainer) -> void:
	MultiplayerText.setup()
	ApplicationMultiplayer.label(body, "Internet / LAN · up to 8 players · matching game versions required.")
	coop.lobby = VBoxContainer.new()
	body.add_child(coop.lobby)
	role = OptionButton.new()
	role.add_item("Host game")
	role.add_item("Join / Reconnect")
	coop.lobby.add_child(role)
	var identity := HBoxContainer.new()
	coop.lobby.add_child(identity)
	var names := column(identity, 2)
	coop.player = ApplicationMultiplayer.field(names, "Player name", "Mayor")
	var colors := column(identity, 1)
	ApplicationMultiplayer.label(colors, "Player colour")
	var swatches := HBoxContainer.new()
	colors.add_child(swatches)
	var selection := ButtonGroup.new()
	coop.color_picker = ColorPickerButton.new()
	coop.color_picker.color = Color("46b4ff")
	coop.color_picker.edit_alpha = false
	coop.color_picker.text = "…"
	coop.color_picker.tooltip_text = "Custom colour…"
	coop.color_picker.custom_minimum_size = Vector2(34, 28)
	for value in ["46b4ff", "ff9c40", "66cf79", "e77ba8", "c7a0ff", "ffe173"]:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = selection
		button.custom_minimum_size = Vector2(22, 28)
		var image := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		image.fill(Color(value))
		button.icon = ImageTexture.create_from_image(image)
		button.tooltip_text = "#" + value
		button.button_pressed = value == "46b4ff"
		swatches.add_child(button)
		button.pressed.connect(func() -> void:
			coop.color_picker.color = Color(value)
			coop.color_picker.color_changed.emit(Color(value)))
		coop.color_picker.color_changed.connect(func(color: Color) -> void:
			button.set_pressed_no_signal(color.to_html(false) == value))
	swatches.add_child(coop.color_picker)
	var picker := coop.color_picker.get_picker()
	picker.presets_visible = false
	picker.color_modes_visible = false
	var popup := coop.color_picker.get_popup()
	var color_body := VBoxContainer.new()
	popup.remove_child(picker)
	popup.add_child(color_body)
	color_body.add_child(picker)
	ApplicationMultiplayer.button(color_body, "Apply colour", func() -> void:
		coop.color_picker.color = picker.color
		coop.color_picker.color_changed.emit(picker.color)
		popup.hide())
	host_fields = VBoxContainer.new()
	coop.lobby.add_child(host_fields)
	lan_only = CheckBox.new()
	lan_only.text = "LAN only"
	host_fields.add_child(lan_only)
	auto_forward = CheckBox.new()
	auto_forward.text = "Automatically forward port (UPnP)"
	auto_forward.tooltip_text = "Allow the router to open the game port while hosting. Existing rules are kept. Your firewall must also allow the game."
	auto_forward.button_pressed = true
	host_fields.add_child(auto_forward)
	visibility_hint = ApplicationMultiplayer.label(host_fields, "Game name, host name, player count and host IP address are publicly listed online.")
	forwarding_hint = ApplicationMultiplayer.label(host_fields, "Internet hosting: forward the TCP port below to this computer in your router and allow it in your firewall. Joining players need no port forwarding.")
	lan_only.toggled.connect(func(_value: bool) -> void: update())
	ApplicationMultiplayer.label(host_fields, "Game mode")
	coop.mode_picker = OptionButton.new()
	for title in ["Co-op", "Competitive Shared", "Competitive Region"]:
		coop.mode_picker.add_item(title)
	host_fields.add_child(coop.mode_picker)
	ApplicationMultiplayer.label(host_fields, "City")
	coop.city_picker = OptionButton.new()
	coop.city_picker.add_item("New city")
	coop.city_picker.add_item("Saved city")
	host_fields.add_child(coop.city_picker)
	coop.use_current = CheckBox.new()
	coop.use_current.text = "Create a copy"
	coop.use_current.tooltip_text = "Keep the selected save unchanged and save this game separately."
	coop.use_current.button_pressed = true
	host_fields.add_child(coop.use_current)
	shared_fields = VBoxContainer.new()
	host_fields.add_child(shared_fields)
	ApplicationMultiplayer.label(shared_fields, "Neutral land price per tile")
	land_price = SpinBox.new()
	land_price.min_value = 0
	land_price.max_value = 1000
	land_price.value = 5
	land_price.prefix = "$"
	shared_fields.add_child(land_price)
	land_price.tooltip_text = "Price for additional neutral land. At the shared start, every city receives an equal free starting area; its treasury stays intact. Saved games retain their rules."
	goal_fields = VBoxContainer.new()
	host_fields.add_child(goal_fields)
	ApplicationMultiplayer.label(goal_fields, "Victory goal")
	goal_picker = OptionButton.new()
	for title in ["Endless game", "Population", "Wealth (funds minus debt)", "Points after game time"]:
		goal_picker.add_item(title)
	goal_fields.add_child(goal_picker)
	goal_target = SpinBox.new()
	goal_target.min_value = 1
	goal_target.max_value = 2147483647
	goal_target.value = 10000
	goal_fields.add_child(goal_target)
	years_label = ApplicationMultiplayer.label(goal_fields, "Required leadership")
	goal_years = OptionButton.new()
	for years in [1, 3, 5, 10]:
		goal_years.add_item(tr("%d game years") % years)
	goal_years.select(3)
	goal_fields.add_child(goal_years)
	goal_years.tooltip_text = "Only the sole leader at or above the target earns time. Earned time is kept; ties pause all clocks."
	duration_label = ApplicationMultiplayer.label(goal_fields, "Duration in game years")
	duration = SpinBox.new()
	duration.min_value = 1
	duration.max_value = 100
	duration.value = 10
	duration.tooltip_text = "Starts when the host starts the game. The lobby shows the end year. Paused game time does not count."
	goal_fields.add_child(duration)
	goal_picker.item_selected.connect(func(index: int) -> void:
		goal_target.value = 100000 if index == 2 else 10000
		update())
	join_tabs = TabBar.new()
	join_tabs.add_tab("Internet")
	join_tabs.add_tab("LAN")
	coop.lobby.add_child(join_tabs)
	join_tabs.tab_changed.connect(func(_index: int) -> void: update())
	internet_browser = MultiplayerLanBrowser.new()
	coop.lobby.add_child(internet_browser)
	internet_browser.setup(coop, true)
	lan_browser = MultiplayerLanBrowser.new()
	coop.lobby.add_child(lan_browser)
	lan_browser.setup(coop)
	advanced = CheckButton.new()
	advanced.text = "Advanced: direct connection"
	coop.lobby.add_child(advanced)
	advanced.toggled.connect(func(_value: bool) -> void: update())
	network = HBoxContainer.new()
	coop.lobby.add_child(network)
	address_box = column(network, 2)
	coop.address = ApplicationMultiplayer.field(address_box, "Host address", "127.0.0.1")
	var ports := column(network, 1)
	ApplicationMultiplayer.label(ports, "TCP port")
	coop.port = SpinBox.new()
	coop.port.min_value = 1024
	coop.port.max_value = 65535
	coop.port.value = 20000
	ports.add_child(coop.port)
	compatibility = MultiplayerCompatibility.new()
	coop.panel.add_child(compatibility)
	compatibility_status = ApplicationMultiplayer.label(coop.lobby, "Compatibility is checked before joining. Visual packs may differ.")
	compatibility_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	compatibility.completed.connect(coop.compatibility_checked)
	coop.panel.visibility_changed.connect(func() -> void:
		if not coop.panel.visible:
			coop.cancel_compatibility())
	coop.address.text_changed.connect(func(_value: String) -> void: coop.cancel_compatibility())
	coop.port.value_changed.connect(func(_value: float) -> void: coop.cancel_compatibility())
	coop.player.text_changed.connect(func(_value: String) -> void: coop.cancel_compatibility())
	password_label = ApplicationMultiplayer.label(coop.lobby, "")
	coop.join_code = LineEdit.new()
	coop.join_code.secret = true
	coop.lobby.add_child(coop.join_code)
	action = ApplicationMultiplayer.button(coop.lobby, "", func() -> void:
		if role.selected == 0:
			coop.start_host()
		else:
			coop.start_join())
	role.item_selected.connect(func(_index: int) -> void:
		coop.cancel_compatibility()
		update())
	coop.mode_picker.item_selected.connect(func(_index: int) -> void: update())
	coop.city_picker.item_selected.connect(func(_index: int) -> void:
		coop.selected_city_path = ""
		update())
	role.tooltip_text = "Host a game on this computer, or connect to an existing host."
	coop.player.tooltip_text = "Your name in the lobby, chat and scoreboard."
	coop.color_picker.tooltip_text = "Choose a custom colour for your cursor, territory and statistics, then Apply colour."
	coop.address.tooltip_text = "Enter the host computer's LAN address or reachable IP address."
	coop.port.tooltip_text = "The host and joining players must use the same TCP port."
	coop.mode_picker.tooltip_text = "Co-op: one shared city. Shared: separate cities on one map. Region: independent neighbouring city maps."
	coop.city_picker.tooltip_text = "Generate new terrain, or continue a saved multiplayer game. Saved games keep their rules and player seats."
	update()

func update() -> void:
	for index in goal_years.item_count:
		goal_years.set_item_text(index, tr("%d game years") % [1, 3, 5, 10][index])
	var hosting := role.selected == 0
	host_fields.visible = hosting
	compatibility_status.visible = not hosting
	visibility_hint.text = "Visible on the local network only." if lan_only.button_pressed else "Game name, host name, player count and host IP address are publicly listed online."
	auto_forward.visible = not lan_only.button_pressed
	forwarding_hint.visible = not lan_only.button_pressed
	forwarding_hint.tooltip_text = "Use the same external and internal TCP port. Internet hosting needs a reachable public address; CGNAT or DS-Lite may prevent incoming connections."
	join_tabs.visible = not hosting
	join_tabs.set_tab_title(0, tr("Internet"))
	join_tabs.set_tab_title(1, tr("LAN"))
	advanced.visible = not hosting
	network.visible = hosting or advanced.button_pressed
	address_box.visible = not hosting
	lan_browser.visible = not hosting and join_tabs.current_tab == 1 and not advanced.button_pressed
	internet_browser.visible = not hosting and join_tabs.current_tab == 0 and not advanced.button_pressed
	lan_browser.sync_visibility()
	lan_browser.refresh()
	internet_browser.sync_visibility()
	internet_browser.refresh()
	password_label.text = "Password (optional)" if hosting else "Password"
	action.text = "Create game" if hosting else "Join / Reconnect"
	coop.use_current.visible = coop.city_picker.selected == 1
	shared_fields.visible = coop.mode_picker.selected == 1 and coop.city_picker.selected == 0
	goal_fields.visible = coop.mode_picker.selected != 0 and coop.city_picker.selected == 0
	goal_target.visible = goal_picker.selected in [1, 2]
	duration.visible = goal_picker.selected == 3
	duration_label.visible = duration.visible
	goal_years.visible = goal_target.visible
	years_label.visible = goal_target.visible
	goal_picker.tooltip_text = goal_help()
	goal_target.tooltip_text = goal_help()
	coop.join_code.tooltip_text = "Leave empty to allow joining without a password." if hosting else "Enter the game's password if the host set one; otherwise leave empty."
	action.tooltip_text = "Configure the city, then wait in the lobby until everyone is ready." if hosting else "Connect and select a new or reserved player seat. The host controls the game rules."
	fit.call_deferred()

func fit() -> void:
	if not is_instance_valid(coop.panel):
		return
	if coop.panel.has_meta("multiplayer_fit"):
		coop.panel.get_meta("multiplayer_fit").schedule()

static func column(parent: Control, ratio: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = ratio
	parent.add_child(box)
	return box

func goal_help() -> String:
	if goal_picker.selected == 3:
		return MultiplayerGoal.score_help()
	var hint := tr("Population: residents of your own city. Suggested targets: 2,000 for a short development goal, 10,000 for a medium goal, 50,000 for a long goal.") if goal_picker.selected == 1 else tr("Net wealth: treasury minus bank bonds and outstanding player debt. Suggested targets: $50,000, $100,000 or $500,000 for increasingly long economic goals.")
	if goal_picker.selected == 0:
		return tr("Build without a victory target or time limit.")
	return hint + "\n" + tr("Reach the target and accumulate the selected number of years as sole leader. Earned time is kept when overtaken; ties pause all clocks.")
