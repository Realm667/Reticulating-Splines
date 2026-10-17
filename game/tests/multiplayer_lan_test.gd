extends SceneTree

const Fixture = preload("res://tests/support/app_fixture.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func find_games(scanner: MultiplayerLanDiscovery, count: int) -> void:
	check(scanner.search() == OK, "search binds an ephemeral UDP socket")
	var until := Time.get_ticks_msec() + 2000
	while scanner.results.size() < count and Time.get_ticks_msec() < until:
		await create_timer(0.01).timeout
	check(scanner.results.size() == count, "real UDP discovery receives all hosts")


func run() -> void:
	var hosts: Array[CoopSession] = []
	var scanner := MultiplayerLanDiscovery.new()
	scanner.targets = PackedStringArray(["127.0.0.1"])
	scanner.ports.clear()
	root.add_child(scanner)
	for index in 2:
		var host := CoopSession.new()
		root.add_child(host)
		host.lan = MultiplayerLanDiscovery.new()
		host.lan.ports = [0]
		host.add_child(host.lan)
		check(host.host(Sc2xDocument.create_empty(32, "LAN city").document, 0, "secret" if index == 0 else "", "Host", "coop", index == 0).is_empty(), "host starts")
		scanner.ports.append(host.lan.responder.get_local_port())
		hosts.append(host)
	await find_games(scanner, 2)
	var lobby := hosts[0].lan_description()
	check(lobby.phase == "lobby" and lobby.locked and lobby.players == 1, "lobby and password flag")
	check(hosts[1].lan_description().phase == "running", "running game is discoverable")
	check(not JSON.stringify(scanner.results).contains("secret"), "password is never advertised")
	check(scanner.results.values()[0].port == hosts[0].server.get_local_port() or scanner.results.values()[1].port == hosts[0].server.get_local_port(), "custom TCP port advertised")
	var valid := lobby.duplicate(true)
	valid.merge({"magic": MultiplayerLanDiscovery.MAGIC, "version": 1, "type": "offer", "nonce": scanner.nonce})
	var original_count := scanner.results.size()
	for field in ["nonce", "port", "players", "session", "mode", "locked"]:
		var bad := valid.duplicate(true)
		bad[field] = []
		scanner.accept_offer(JSON.stringify(bad).to_utf8_buffer(), "127.0.0.1", 0)
	check(scanner.results.size() == original_count, "malformed replies ignored")
	scanner.accept_offer("[]".to_utf8_buffer(), "127.0.0.1", 0)
	scanner.accept_offer("{".to_utf8_buffer(), "127.0.0.1", 0)
	scanner.accept_offer("x".repeat(2000).to_utf8_buffer(), "127.0.0.1", 0)
	check(scanner.results.size() == 2, "invalid and oversized datagrams ignored")
	scanner.accept_offer(JSON.stringify(valid).to_utf8_buffer(), "127.0.0.1", Time.get_ticks_msec())
	check(scanner.results.size() == 2, "duplicate offers coalesce")
	scanner.deadline = 0
	scanner._process(0)
	check(not scanner.searching and scanner.seeker == null and scanner.results.size() == 2, "search ends and closes its socket, keeps results")
	for key: String in scanner.results:
		scanner.results[key].seen = -MultiplayerLanDiscovery.RESULT_MSEC
	scanner._process(0)
	check(scanner.results.is_empty(), "stale entries expire")
	hosts[1].stop()
	check(hosts[1].lan.responder == null and hosts[1].lan_description().is_empty(), "leaving stops advertisement")
	await find_games(scanner, 1)
	scanner.cancel_search(true)
	check(not scanner.is_processing(), "idle scanner does no polling")
	await browser_case(hosts[0])
	for host in hosts:
		host.stop()
		host.queue_free()
	scanner.queue_free()
	await process_frame
	print("Multiplayer LAN checks: %d failures" % failures)
	quit(1 if failures else 0)


func browser_case(host: CoopSession) -> void:
	root.gui_embed_subwindows = true
	var app: CityApplication = load("res://main.tscn").instantiate()
	Fixture.configure(app, true)
	root.add_child(app)
	await process_frame
	app.coop.open()
	app.coop.launch.role.select(1)
	app.coop.launch.join_tabs.current_tab = 1
	app.coop.launch.update()
	var browser := app.coop.launch.lan_browser
	check(browser.visible, "join role exposes LAN browser")
	browser.discovery.targets = PackedStringArray(["127.0.0.1"])
	browser.discovery.ports = [host.lan.responder.get_local_port()]
	browser.start_search()
	var until := Time.get_ticks_msec() + 2000
	while browser.discovery.results.is_empty() and Time.get_ticks_msec() < until:
		await create_timer(0.01).timeout
	var row := browser.games.get_root().get_first_child()
	check(row != null, "browser shows real UDP host")
	if row != null:
		row.select(0)
		browser.select_game()
		check(app.coop.address.text == "127.0.0.1" and int(app.coop.port.value) == host.server.get_local_port(), "select fills endpoint")
		check(not app.coop.session.active, "selection does not silently join")
		var key: String = row.get_metadata(0)
		browser.discovery.results[key].build = "different"
		browser.refresh()
		check(not browser.games.get_root().get_first_child().is_selectable(0), "incompatible build cannot be selected")
		browser.discovery.results[key].build = CoopSession.NETWORK_BUILD
		browser.discovery.results[key].open = false
		browser.refresh()
		check(not browser.games.get_root().get_first_child().is_selectable(0), "full game cannot be selected")
	app.coop.panel.hide()
	check(browser.discovery.seeker == null and browser.discovery.results.is_empty(), "closing browser cancels search")
	app.coop.open()
	app.coop.launch.role.select(0)
	app.coop.launch.update()
	check(not browser.visible, "host role hides search")
	app.queue_free()
	await process_frame
