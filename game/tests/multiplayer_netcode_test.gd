extends SceneTree
## Ordered brush batching, unchanged archive bytes, reserved rings and a real
## loopback connection with latency, jitter, fragmentation and a reconnect.
@warning_ignore_start("integer_division")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func wait_for(predicate: Callable) -> bool:
	var until := Time.get_ticks_msec() + 20000
	while not predicate.call() and Time.get_ticks_msec() < until:
		await process_frame
	return predicate.call()

func build(id: int, revision: int, point: Vector2i) -> Dictionary:
	return {"id": id, "kind": "build", "revision": revision, "group": CityToolIds.Group.WATER,
		"tool": CityToolIds.Water.PUMP, "start": [point.x, point.y], "finish": [point.x, point.y],
		"path": [], "dragged": false}

func run() -> void:
	framed_backlog()
	archive_cache()
	incremental_statistics()
	await direct_documents()
	reservation_delta()
	reservation_ring()
	municipal_policy_isolation()
	incremental_shared()
	land_constraints()
	causal_commands()
	await shaped_connection()
	print("Multiplayer netcode checks: %d failures" % failures)
	quit(1 if failures else 0)

func framed_backlog() -> void:
	var sender := CityTcpChannel.new()
	for index in 100:
		sender.send({"type": "command", "id": index, "text": "Straße · 도시"})
	var receiver := CityTcpChannel.new()
	var split := sender.output.size() - 5
	receiver.input = sender.output.slice(0, split)
	var ids: Array = []
	while true:
		var batch := receiver.decode_messages(7)
		if batch.is_empty():
			break
		check(batch.size() <= 7, "message budget remains bounded")
		for message: Dictionary in batch:
			ids.append(int(message.id))
	check(ids == range(99) and not receiver.failed, "fragmented burst retains order without duplicating commands")
	receiver.input.append_array(sender.output.slice(split))
	var last := receiver.decode_messages(7)
	check(last.size() == 1 and int(last[0].id) == 99 and receiver.input.is_empty(), "partial final frame completes exactly once")
	receiver.input = sender.output.slice(0, 4)
	receiver.input.encode_u32(0, CityTcpChannel.MAX_FRAME + 1)
	check(receiver.decode_messages(7).is_empty() and receiver.failed, "oversized frame is still rejected")

func direct_documents() -> void:
	var source := Sc2xDocument.create_empty(32, "Direct document").document
	source.sc2x_extra_entries["unknown.data"] = PackedByteArray([17, 83, 0, 255])
	var cache := MultiplayerDocument.new()
	var snapshot := cache.capture(source).merged({"type": "state", "revision": 0})
	var job := MultiplayerWireJob.new()
	job.start(snapshot)
	check(await wait_for(job.ready), "background encoder completes")
	job.finish()
	var envelope: Dictionary = JSON.parse_string(job.bytes.get_string_from_utf8())
	var unpack := MultiplayerWireJob.new()
	unpack.start(envelope, true)
	check(await wait_for(unpack.ready), "background decoder completes")
	unpack.finish()
	check(not unpack.failed, "compressed state passes digest validation")
	var restored := MultiplayerDocument.restore(unpack.decoded)
	check(restored != null, "direct document restores after real JSON and compression")
	if restored == null:
		return
	check(Sc2xDocument.encode(restored).data == Sc2xDocument.encode(source).data, "direct document preserves complete save bytes and unknown extras")
	var sender := MultiplayerDelta.new()
	var receiver := MultiplayerDelta.new()
	receiver.decode(sender.encode(snapshot))
	CityState.from_document(source).set_funds(54321)
	var changed := cache.capture(source).merged({"type": "state", "revision": 1})
	var wire := sender.encode(changed)
	check(wire.pages.size() == 1, "finance change sends only its changed chunk page")
	var decoded := receiver.decode(wire)
	var next := MultiplayerDocument.restore(decoded, snapshot, restored)
	check(next != null and next.find_chunk("ALTM") == restored.find_chunk("ALTM"), "unchanged client terrain buffer is reused")
	check(next != null and Sc2xDocument.encode(next).data == Sc2xDocument.encode(source).data, "incremental document matches authoritative archive exactly")
	var invalid := changed.duplicate(true)
	invalid.document.layout[0][1] += 1
	check(MultiplayerDocument.restore(invalid) == null, "mismatched chunk lengths rejected")
	envelope.sha256 = "invalid"
	var corrupt := MultiplayerWireJob.new()
	corrupt.start(envelope, true)
	await wait_for(corrupt.ready)
	corrupt.finish()
	check(corrupt.failed and corrupt.decoded.is_empty(), "corrupt compressed state rejected")
	var canceled := MultiplayerWireJob.new()
	canceled.start(snapshot)
	canceled.finish()
	check(canceled.task == -1 and canceled.input.is_empty(), "shutdown joins outstanding codec work")

func reservation_delta() -> void:
	var sender := MultiplayerDelta.new()
	var receiver := MultiplayerDelta.new()
	var protected: Array = []
	protected.resize(5000)
	protected.fill(0)
	var state := {"type": "state", "city": "test", "revision": 1, "protection": protected}
	receiver.decode(sender.encode(state))
	protected[4999] = 2
	state.revision = 2
	var wire := sender.encode(state)
	check(wire.pages.protection.chunks.size() == 1, "only changed reservation page travels")
	var restored := receiver.decode(wire)
	check(not receiver.failed and restored.protection[4999] == 2, "reservation pages reconstruct exactly")
	wire.base = restored.wire_id
	wire.pages.protection.chunks[0][1] = "invalid"
	check(receiver.decode(wire).is_empty() and receiver.failed, "malformed reservation patch rejected atomically")

func incremental_statistics() -> void:
	var world := SharedWorld.new()
	world.open(Sc2xDocument.create_empty(32, "Incremental statistics").document)
	world.add_player("a".repeat(48))
	world.add_player("b".repeat(48))
	for pass_index in 4:
		for actor: String in world.actors:
			var child: CoopWorld = world.municipalities[actor]
			for tile in [0, 511, 512, 1023]:
				world.owners[tile] = (pass_index + tile) % 3
				child.city.buildings[tile] = 0 if pass_index == 3 else 20 + pass_index
				child.city.zones[tile] = pass_index * 2
			var incremental := MultiplayerStatistics.capture(world, actor)
			child.statistics_tiles.clear()
			check(incremental == MultiplayerStatistics.capture(world, actor), "incremental ownership, demolition and zone counts equal a fresh full scan")

func archive_cache() -> void:
	var doc := Sc2xDocument.create_empty(32, "Cached archive").document
	doc.sc2x_extra_entries["unknown.data"] = PackedByteArray([17, 83, 0, 255])
	var cache := {}
	for funds in [12345, 12346, 12346]:
		CityState.from_document(doc).set_funds(funds)
		var ordinary := Sc2xDocument.encode(doc)
		var cached := Sc2xDocument.encode(doc, cache)
		check(cached.ok and ordinary.data == cached.data, "cached encoding is byte-identical, including unknown entries")
		doc.sc2x_extra_entries["unknown.data"] = PackedByteArray([9, 8, 7])
	# The integrated runtime uses the native codec rather than the feature
	# branch's GDScript member cache. Byte identity above covers that adapter.
	var snapshot := CoopWorld.new()
	snapshot.open(doc)
	var before := MultiplayerStatistics.capture(snapshot, "host")
	snapshot.command("host", build(1, snapshot.revision, Vector2i(4, 4)))
	var after := MultiplayerStatistics.capture(snapshot, "host")
	check(after.built == before.built + 1 and after.funds < before.funds, "cached statistics follow real edits")

func reservation_ring() -> void:
	var world := SharedWorld.new()
	world.open(Sc2xDocument.create_empty(64, "Reservation").document)
	world.add_player("a".repeat(48))
	world.add_player("b".repeat(48))
	var starts := MultiplayerStarts.new()
	check(starts.prepare(world, {"a".repeat(48): {}, "b".repeat(48): {}}).is_empty(), "start allocation succeeds")
	for actor: String in world.actors:
		var reserve_count := 0
		for value: int in world.protection:
			if value == world.actors.find(actor) + 1:
				reserve_count += 1
		check(reserve_count == starts.positions[actor].reserved, "entire promised reserve remains protected without a carved corridor")
	check(world.protection[32 * 64 + 32] == 0, "empty sector seams are purchasable")
	for slot in [0, 5, 15]:
		var empty := PackedInt32Array()
		empty.resize(64 * 64)
		var parcel := MultiplayerStartParcel.make(world.city, empty, slot, 50)
		var bounds := MultiplayerLandMarket.tile_bounds(parcel.tiles, 64)
		check(bounds.get_area() == parcel.tiles.size(), "start is a complete rectangle")
		check(maxf(bounds.size.x, bounds.size.y) / minf(bounds.size.x, bounds.size.y) <= 1.25, "start remains near square")
		var complete: Array = parcel.tiles.duplicate()
		complete.append_array(parcel.reserve)
		check(MultiplayerLandMarket.tile_bounds(complete, 64).get_area() == complete.size(), "reserve forms a complete surrounding rectangle")
		if slot == 0:
			check(bounds.position == Vector2i.ZERO, "corner start touches actual map boundary")
	world.protection[32 * 64 + 32] = -1
	var saved := world.saved_shared()
	var restored := SharedWorld.new()
	check(restored.open(world.city.document) and restored.restore_shared(saved).is_empty(), "legacy seam save restored")
	check(restored.protection[32 * 64 + 32] == 0 and restored.owners == world.owners, "legacy empty seams released without changing ownership")

func municipal_policy_isolation() -> void:
	for region in [false, true]:
		var world: SharedWorld = RegionWorld.new() if region else SharedWorld.new()
		world.open(Sc2xDocument.create_empty(32, "Policies").document)
		world.add_player("a".repeat(48))
		world.add_player("b".repeat(48))
		var other: CoopWorld = world.municipalities["a".repeat(48)]
		var own: CoopWorld = world.municipalities["b".repeat(48)]
		var unchanged := other.city.document.find_chunk("MISC").decoded_payload.duplicate()
		var values := Array(BudgetPhase.funding_values(own.city))
		values[0] = 11
		for action in [{"kind":"budget", "values":values,"auto":true}, {"kind":"ordinance","ordinance":0,"enabled":true}, {"kind":"industry_tax","industry":0,"rate":4,"all":false}, {"kind":"bond"}, {"kind":"city_option","option":"newspaper_subscription","enabled":true}]:
			action["revision"] = world.revision
			action["policy"] = own.policy_revision
			check(world.command("b".repeat(48), action).ok, "municipal policy accepted: " + action.kind)
			check(other.city.document.find_chunk("MISC").decoded_payload == unchanged, "policy never changes other municipality: " + action.kind)
		var restored: SharedWorld = RegionWorld.new() if region else SharedWorld.new()
		restored.open(world.city.document)
		check(restored.restore_shared(world.saved_shared()).is_empty(), "municipal budgets reload")
		check(restored.municipalities["b".repeat(48)].city.auto_budget_enabled() and BudgetPhase.funding_values(restored.municipalities["b".repeat(48)].city)[0] == 11, "own funding and auto-budget survive reload")
		check(restored.municipalities["a".repeat(48)].city.document.find_chunk("MISC").decoded_payload == unchanged, "other budget remains independent after reload")

func incremental_shared() -> void:
	var world := SharedWorld.new()
	world.open(Sc2xDocument.create_empty(32, "Composition").document)
	world.add_player("a".repeat(48))
	world.add_player("b".repeat(48))
	world.owners.fill(1)
	for tile in range(512, 1024): world.owners[tile] = 2
	world.snapshot_for("a".repeat(48), true)
	var child: CoopWorld = world.municipalities["b".repeat(48)]
	for tile in [512, 800, 1023]: child.city.document.find_chunk("XBLD").decoded_payload[tile] = 30
	world.revision += 1
	var cached := world.snapshot_for("a".repeat(48), true)
	world.snapshot_cache.clear()
	world.composed_revision = -1
	world.composition_sources.clear()
	world.composed_chunks.clear()
	world.record_overlay_cache.clear()
	world.record_cache.clear()
	check(cached == world.snapshot_for("a".repeat(48), true), "incremental shared composition equals full recomposition across block edges")

func land_constraints() -> void:
	var world := SharedWorld.new()
	world.open(Sc2xDocument.create_empty(64, "Land access").document)
	world.add_player("a".repeat(48))
	world.add_player("b".repeat(48))
	world.owners[30 * 64 + 10] = 1
	world.owners[40 * 64 + 10] = 2
	var request := {"kind":"land_request", "start":[40,10], "finish":[40,10], "revision":world.revision}
	check(not world.command("a".repeat(48),request).ok and world.offers.is_empty(), "disconnected land rejected before asking for a price")
	request.price = 10
	check(not world.command("a".repeat(48),request).ok and world.offers.is_empty(), "disconnected land cannot create an offer")
	var purchased := world.command("a".repeat(48),{"kind":"land_buy", "start":[31,10], "finish":[39,10], "revision":world.revision})
	check(purchased.ok and world.owners[32 * 64 + 10] == 1 and world.owners[39 * 64 + 10] == 1, "purchase crosses the old sector boundary")
	request.revision = world.revision
	check(world.command("a".repeat(48),request).ok and world.offers.size() == 1, "adjacent request is allowed")
	world.owners[39 * 64 + 10] = 0
	var before: int = world.municipalities["a".repeat(48)].city.funds()
	check(not world.command("b".repeat(48),{"kind":"land_accept","offer":world.offers.keys()[0],"revision":world.revision}).ok, "connection is rechecked at acceptance")
	check(world.municipalities["a".repeat(48)].city.funds() == before, "invalidated trade never charges buyer")
	var host := CoopSession.new()
	host.token = "a".repeat(48)
	var heard: Array = []
	host.remote_action_sound.connect(func(event: Dictionary) -> void: heard.append(event))
	host.announce_action("b".repeat(48), {"id":1,"kind":"land_buy"}, purchased)
	check(heard.size() == 1 and heard[0].point == purchased.sound_point, "other player's purchase carries a spatial sound position")
	host.free()

func causal_commands() -> void:
	var host := CoopSession.new()
	root.add_child(host)
	host.host(Sc2xDocument.create_empty(32, "Ordered").document, 0, "", "Host", "coop", false)
	var actor := host.token
	var seen := host.world.revision
	var first := build(1, seen, Vector2i(4, 4))
	check(host.execute(actor, first).ok, "first action accepted")
	check(host.execute(actor, build(2, seen, Vector2i(4, 5))).ok, "own consecutive action before snapshot accepted")
	var funds := host.world.city.funds()
	check(not host.execute(actor, first).ok and host.world.city.funds() == funds, "duplicate never charges twice")
	# An intervening external action must break the causal chain even if it was
	# delivered outside the session wrapper (as simulation steps are).
	var foreign := build(1, host.world.revision, Vector2i(8, 8))
	check(host.world.command("other", foreign).ok, "foreign edit accepted")
	var stale := build(3, seen, Vector2i(8, 8))
	stale.group = CityToolIds.Group.BULLDOZER
	stale.tool = CityToolIds.Bulldozer.DEMOLISH
	check(not host.execute(actor, stale).ok, "own stream never bypasses a foreign conflict")
	host.stop()
	host.queue_free()

func shaped_connection() -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	root.add_child(host)
	root.add_child(guest)
	host.host(Sc2xDocument.create_empty(32, "Shaped TCP").document, 0, "", "Host", "coop", false)
	var link := ShapedLink.new()
	link.destination = host.server.get_local_port()
	check(link.listener.listen(0, "127.0.0.1") == OK, "isolated proxy listens")
	root.add_child(link)
	guest.join("127.0.0.1", link.listener.get_local_port(), "", "Guest")
	check(await wait_for(func() -> bool: return guest.connected), "join over fragmented delayed transport")
	var before := host.world.city.funds()
	var published := host.publication_count
	var start_id := guest.next_command
	for y in range(3, 15):
		guest.request(build(0, guest.local_revision, Vector2i(6, y)))
	check(await wait_for(func() -> bool: return host.members[guest.token].sequence == start_id + 11), "every queued command handled in order")
	check(await wait_for(func() -> bool: return guest.local_revision == host.world.revision), "all accepted changes converge")
	check(host.world.statistics[guest.token].builds == 12 and host.world.city.funds() == before - 12 * 100, "all pumps built and charged exactly once")
	check(host.publication_count - published < 12, "commands share snapshots")
	var acknowledged_funds := host.world.city.funds()
	guest.decoder.states.clear()
	host.publish()
	check(await wait_for(func() -> bool: return guest.resync_requested), "missing delta base triggers repair")
	check(await wait_for(func() -> bool: return not guest.resync_requested and guest.local_revision == host.world.revision), "full baseline repairs without stale rollback")
	check(same_city(host, guest), "repaired city matches authoritative save bytes")
	link.disconnect_peers()
	check(await wait_for(func() -> bool: return not guest.connected), "connection interruption detected")
	check(await wait_for(func() -> bool: return guest.connected), "same identity reconnects through proxy")
	check(guest.next_command == start_id + 12 and host.world.city.funds() == acknowledged_funds, "reconnect preserves sequence and does not replay payments")
	check(same_city(host, guest), "reconnected document matches authoritative document")
	guest.stop()
	host.stop()
	link.disconnect_peers()
	link.listener.stop()
	link.queue_free()
	guest.queue_free()
	host.queue_free()
	await process_frame

func same_city(host: CoopSession, guest: CoopSession) -> bool:
	var authoritative := MultiplayerDocument.restore(host.latest)
	var received := MultiplayerDocument.restore(guest.latest)
	return authoritative != null and received != null and Sc2xDocument.encode(authoritative).data == Sc2xDocument.encode(received).data

class ShapedLink extends Node:
	var listener := TCPServer.new()
	var destination := 0
	var peers: Array[StreamPeerTCP] = []
	var queues: Array = [[], []]
	var sequence := 0

	func disconnect_peers() -> void:
		for peer in peers:
			peer.disconnect_from_host()
		peers.clear()
		queues = [[], []]

	func _process(_delta: float) -> void:
		if peers.is_empty() and listener.is_connection_available():
			peers.append(listener.take_connection())
			var target := StreamPeerTCP.new()
			target.connect_to_host("127.0.0.1", destination)
			peers.append(target)
		if peers.is_empty():
			return
		for peer in peers:
			peer.poll()
		for index in 2:
			var source := peers[index]
			var target := peers[1 - index]
			if source.get_status() != StreamPeerTCP.STATUS_CONNECTED or target.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				continue
			var queue: Array = queues[index]
			var now := Time.get_ticks_msec()
			var size := mini(1024, source.get_available_bytes())
			if size > 0:
				var data := source.get_partial_data(size)
				sequence += 1
				var due := now + 30 + (sequence * 13) % 31
				if not queue.is_empty():
					due = maxi(due, int(queue.back()[0]))
				queue.append([due, data[1]])
			if not queue.is_empty() and int(queue[0][0]) <= now:
				var body: PackedByteArray = queue[0][1]
				var sent := target.put_partial_data(body.slice(0, 512))
				if sent[0] == OK:
					queue[0][1] = body.slice(int(sent[1]))
					if queue[0][1].is_empty():
						queue.pop_front()
