extends SceneTree
## Run against the bundled service via server/multiplayer/run_game_test.py.

var failures := 0
const Fixture = preload("res://tests/support/app_fixture.gd")


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func wait_for(predicate: Callable, seconds := 5.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < until:
		await create_timer(0.01).timeout
	return predicate.call()


func run() -> void:
	assert(MultiplayerOnline.base_url().begins_with("http://127.0.0.1:"), "Integration test requires isolated local relay")
	var host := CoopSession.new()
	var guest := CoopSession.new()
	var denied := CoopSession.new()
	for node in [host, guest, denied]:
		root.add_child(node)
	check(host.host(Sc2xDocument.create_empty(128, "Relay city").document, 0, "sample", "Host", "shared", false).is_empty(), "host starts")
	check(host.online == null, "session creation alone does not publish LAN/test games")
	host.publish_online()
	check(await wait_for(func() -> bool: return host.online.registered), "host registered online")
	var app: CityApplication = load("res://main.tscn").instantiate()
	Fixture.configure(app, true)
	root.add_child(app)
	await process_frame
	app.coop.open()
	app.coop.launch.role.select(1)
	app.coop.launch.update()
	var browser := app.coop.launch.internet_browser
	browser.request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		print("Directory response: ", result, ":", code, ":", body.size()))
	browser.start_search()
	check(await wait_for(func() -> bool: return not browser.pending, 10), "directory request finishes")
	check(not browser.last_error and browser.discovery.results.size() == 1, "browser finds real online host")
	if browser.games.get_root().get_first_child() != null:
		browser.games.get_root().get_first_child().select(0)
		browser.select_game()
		check(browser.selected_online == host.online.room, "browser selects relay room")
	app.coop.port.value = 0
	app.coop.launch.lan_only.button_pressed = true
	app.coop.host_document(Sc2xDocument.create_empty(128, "Private city").document)
	check(app.coop.session.hosting and app.coop.session.online == null, "LAN-only host UI never publishes online")
	app.coop.session.stop()
	app.coop.launch.lan_only.button_pressed = false
	app.coop.host_document(Sc2xDocument.create_empty(128, "Public city").document)
	check(await wait_for(func() -> bool: return app.coop.session.online != null and app.coop.session.online.registered), "normal host UI publishes automatically")
	# An unavailable directory must also release its stopped session-local node.
	var stopped_online := app.coop.session.online
	stopped_online.wire.close()
	stopped_online.set_process(false)
	app.coop.session.stop()
	await process_frame
	await process_frame
	check(not is_instance_valid(stopped_online), "failed listing is cleaned up on stop")
	app.queue_free()
	await process_frame
	var address := "relay:" + host.online.room
	denied.join(address, 0, "wrong", "Denied")
	await create_timer(1).timeout
	check(not denied.connected and host.identities.is_empty(), "wrong password grants no authority")
	denied.stop()
	guest.join(address, 0, "sample", "Guest")
	check(await wait_for(func() -> bool: return guest.connected, 10), "relay client receives authoritative city")
	check(guest.latest.get("mode") == "shared", "shared mode and city snapshot arrive")
	var chats: Array = []
	host.chat_received.connect(func(message: Dictionary) -> void: chats.append(message))
	guest.send_chat("relay check")
	check(await wait_for(func() -> bool: return not chats.is_empty()), "client command reaches host")
	var actor := guest.token
	guest.channels[0].close()
	check(await wait_for(func() -> bool: return not guest.connected), "relay loss detected")
	check(await wait_for(func() -> bool: return guest.connected, 12), "normal authenticated reconnect works over relay")
	check(guest.token == actor, "reconnect keeps seat")
	host.stop()
	check(await wait_for(func() -> bool: return not guest.ended_city.is_empty(), 15), "graceful shutdown delivers singleplayer city copy")
	guest.stop()
	for node in [host, guest, denied]:
		node.queue_free()
	await process_frame
	print("Relay integration: %d failure(s)" % failures)
	quit(1 if failures else 0)
