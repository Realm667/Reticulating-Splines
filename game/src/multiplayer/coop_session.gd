class_name CoopSession
extends Node
## One authoritative host, up to eight simultaneous participants, no client simulation.

signal state_received(state: Dictionary)
signal summary_received(state: Dictionary)
signal command_sent(id: int, command: Dictionary)
signal command_completed(id: int)
signal command_resolved(id: int, result: Dictionary)
signal action_sounds(sounds: Array[int])
signal remote_action_sound(event: Dictionary)
var sounded_commands: Dictionary = {}
signal feedback(message: String)
signal session_ended
signal connection_changed
signal choice_requested(result: Dictionary)
signal environment_received(state: Dictionary)
signal chat_received(message: Dictionary)
signal presence_received(players: Array)
signal player_event(event: Dictionary)
signal seats_changed
signal seat_lobby_received(data: Dictionary)

const PROTOCOL := 1
const BUILD := "opensc2k-coop-1"
const NETWORK_BUILD := "opensc2k-multiplayer-22"
const MAX_PLAYERS := 8
var world: CoopWorld
var lan: MultiplayerLanDiscovery
var active := false
var hosting := false
var connected := false
var code := ""
var token := Crypto.new().generate_random_bytes(24).hex_encode()
var credential := ""
var seats: MultiplayerSeats
var local_player_name := ""
var host_land_price := 10
var host_starter_tiles := 0
var host_goal_kind := "endless"
var host_goal_target := 10000
var host_goal_years := 10
var host_duration_years := 10
var goal := MultiplayerGoal.new()
var loans := MultiplayerLoans.new()
var history := MultiplayerHistory.new()
var starts := MultiplayerStarts.new()
var waiting_for_start := false
var lobby_ready: Dictionary = {}
var lobby_generation := 0
var viewed_cities: Dictionary = {}
var session_id := ""
var server: TCPServer
var channels: Dictionary[int, CityTcpChannel] = {}
var identities: Dictionary[int, String] = {}
var members: Dictionary = {}
var next_peer := 1
var next_command := 1
var local_revision := 0
var local_policy := 0
var latest: Dictionary = {}
var snapshot_elapsed := 0.0
var build_publication_pending := false
var build_publication_due := 0
var pending_publications: Dictionary = {}
var received_messages: Dictionary = {}
var wire_jobs: Dictionary = {}
var decode_job: MultiplayerWireJob
var environment_signature: Dictionary = {}
var presence_signature: Array = []
var cursor_signature: Dictionary = {}
var cursor_sent_at := 0
var build_chain: Dictionary = {}
var publication_count := 0
var publication_usec := 0
var heartbeat_elapsed := 0.0
var disconnected_pause := false
var requested_speed: Dictionary = {}
var handshake_started: Dictionary[int, int] = {}
var command_rates: Dictionary[int, Array] = {}
var environment_source: Callable
var environment_elapsed := 0.0
var player_color := "46b4ff"
var cursors: Dictionary = {}
var cursor_tools: Dictionary = {}
var cursor_tool_source: Callable
var cursor_updated: Dictionary = {}
var chat_history: Array = []
var presence_elapsed := 0.0
var selection_source: Callable
var selections: Dictionary = {}
var cursor_source: Callable
var chat_last_sent: Dictionary = {}
var event_sequence := 0
var admin_history: Array = []
var graceful_peers: Dictionary = {}
var statistics_cache: Dictionary = {}
var statistics_revision := -1
var common_state: Dictionary = {}
var common_revision := -1
var published_revision := -1
var published_policy := -1
var outgoing_states: Dictionary = {}
var incoming_state: MultiplayerStateStream
var retiring_channels: Array = []
var ended_city := ""
var confirmed_own_city := ""
var confirmed_own_state: Dictionary = {}
var encoders: Dictionary = {}
var decoder := MultiplayerDelta.new()
var reconnect_endpoint: Dictionary = {}
var reconnect_until := 0
var reconnect_at := 0
var reconnect_attempt := 0
var resync_requested := false
var command_started: Dictionary = {}
var acknowledgement_usec: Array[int] = []
var interest := MultiplayerInterest.new()
var interest_source: Callable
var interest_signature: Dictionary = {}
var summary_signature: Dictionary = {}
const SUMMARY_FIELDS := ["roster", "goal", "loans", "history", "offers", "land_history", "admin_history", "lobby", "round", "starts", "start_preview"]



func _init() -> void:
	seats = MultiplayerSeats.new(self)


func ensure_credential() -> void:
	if credential.is_empty():
		credential = token


func _exit_tree() -> void:
	if lan != null:
		lan.stop_advertising()
	close_wire_jobs()
	for retired: Dictionary in retiring_channels:
		for stream: MultiplayerStateStream in retired.get("streams", []):
			stream.close()
		retired.channel.close()
	for stream: MultiplayerStateStream in outgoing_states.values():
		stream.close()
	if incoming_state != null:
		incoming_state.close()


func host(document: Sc2File, port: int, join_code: String, player_name: String, mode := "coop", use_lobby := true) -> String:
	var candidate: CoopWorld = RegionWorld.new() if mode == "region" else SharedWorld.new() if mode == "shared" else CoopWorld.new()
	if candidate is SharedWorld:
		candidate.land_price = host_land_price
		candidate.starter_tiles = host_starter_tiles
	if not candidate.open(document):
		return candidate.error
	var listener := TCPServer.new()
	var result := listener.listen(port)
	if result != OK:
		return "Cannot listen on TCP port %d: %s" % [port, error_string(result)]
	ensure_credential()
	stop()
	token = credential
	local_player_name = player_name
	goal = MultiplayerGoal.new()
	goal.kind = host_goal_kind if mode != "coop" else "endless"
	goal.target = host_goal_target
	goal.hold_days = host_goal_years * CityCalendar.DAYS_PER_YEAR
	goal.duration_days = clampi(host_duration_years, 1, 100) * CityCalendar.DAYS_PER_YEAR
	world = candidate
	if world is SharedWorld:
		var shared_error: String = world.add_player(token)
		if not shared_error.is_empty():
			listener.stop()
			return shared_error
	server = listener
	code = join_code
	session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	members[token] = {"name": player_name.left(32), "sequence": 0, "color": player_color}
	seats.credentials[credential.sha256_text()] = token
	members[token]["seat_status"] = "connected"
	requested_speed[token] = 1
	active = true
	hosting = true
	connected = true
	goal.reset_clock(world)
	if not use_lobby:
		goal.begin(world)
	waiting_for_start = use_lobby
	if lan == null:
		lan = MultiplayerLanDiscovery.new()
		add_child(lan)
	# Discovery is optional: an unavailable UDP port must not prevent direct TCP play.
	lan.advertise(lan_description)
	apply_speed()
	publish()
	connection_changed.emit()
	return ""


func lan_description() -> Dictionary:
	if not active or not hosting or server == null or not server.is_listening() or world == null:
		return {}
	return {"session": session_id, "port": server.get_local_port(), "build": NETWORK_BUILD,
		"host": MultiplayerLanDiscovery.plain_name(local_player_name),
		"city": MultiplayerLanDiscovery.plain_name(world.city.document.city_name()),
		"mode": "region" if world is RegionWorld else "shared" if world is SharedWorld else "coop",
		"phase": "lobby" if waiting_for_start else "running", "locked": not code.is_empty(),
		"players": requested_speed.size(), "open": channels.size() < MAX_PLAYERS - 1}


func join(address: String, port: int, join_code: String, player_name: String, intent := "new") -> String:
	ensure_credential()
	local_player_name = player_name
	reconnect_endpoint = {"address": address, "port": port, "code": join_code, "name": player_name, "intent": intent}
	resync_requested = false
	if active and hosting:
		return "Leave the hosted session first."
	if incoming_state != null:
		incoming_state.close()
		incoming_state = null
	decoder = MultiplayerDelta.new()
	var peer := StreamPeerTCP.new()
	var result := peer.connect_to_host(address, port)
	if result != OK:
		return "Cannot connect: %s" % error_string(result)
	for channel in channels.values():
		channel.close()
	channels.clear()
	active = true
	hosting = false
	connected = false
	code = join_code
	var channel := CityTcpChannel.new(peer)
	channels[0] = channel
	channel.send({"type": "hello", "protocol": PROTOCOL, "build": NETWORK_BUILD, "code": code,
		"token": credential, "name": player_name.left(32), "session": session_id, "color": player_color, "intent": intent})
	connection_changed.emit()
	return ""


func stop() -> void:
	if lan != null:
		lan.stop_advertising()
	close_wire_jobs()
	build_publication_pending = false
	build_chain.clear()
	pending_publications.clear()
	interest = MultiplayerInterest.new()
	interest_signature.clear()
	summary_signature.clear()
	received_messages.clear()
	environment_signature.clear()
	presence_signature.clear()
	cursor_signature.clear()
	snapshot_elapsed = 0.0
	ended_city = ""
	confirmed_own_city = ""
	confirmed_own_state.clear()
	reconnect_until = 0
	reconnect_endpoint.clear()
	reconnect_attempt = 0
	if incoming_state != null:
		incoming_state.close()
		incoming_state = null
	if active and connected:
		for id: int in channels:
			var channel: CityTcpChannel = channels[id]
			channel.ephemeral.clear()
			if hosting:
				channel.send({"type": "ending"})
			var streams: Array = []
			if outgoing_states.has(id):
				streams.append(outgoing_states[id])
				outgoing_states.erase(id)
			if hosting and identities.has(id):
				var converted := MultiplayerSingleplayer.from_world(world, identities[id])
				if converted.error.is_empty():
					var encoded := Sc2xDocument.encode(converted.document)
					if encoded.ok:
						var stream := MultiplayerStateStream.new()
						if stream.open_output({"type": "state", "ended_copy": Marshalls.raw_to_base64(encoded.data)}):
							streams.append(stream)
			retiring_channels.append({"channel": channel, "until": Time.get_ticks_msec() + 60000, "streams": streams, "sent_leave": false})
	for stream: MultiplayerStateStream in outgoing_states.values():
		stream.close()
	outgoing_states.clear()
	graceful_peers.clear()
	encoders.clear()
	decoder = MultiplayerDelta.new()
	statistics_cache.clear()
	statistics_revision = -1
	common_state.clear()
	common_revision = -1
	published_revision = -1
	published_policy = -1
	for channel in channels.values():
		if not active or not connected:
			channel.close()
	channels.clear()
	identities.clear()
	handshake_started.clear()
	command_rates.clear()
	if server != null:
		server.stop()
	server = null
	world = null
	members.clear()
	seats.clear()
	viewed_cities.clear()
	goal = MultiplayerGoal.new()
	loans = MultiplayerLoans.new()
	history = MultiplayerHistory.new()
	starts = MultiplayerStarts.new()
	waiting_for_start = false
	lobby_ready.clear()
	cursors.clear()
	cursor_tools.clear()
	selections.clear()
	cursor_updated.clear()
	admin_history.clear()
	chat_history.clear()
	chat_last_sent.clear()
	requested_speed.clear()
	sounded_commands.clear()
	command_started.clear()
	active = false
	connected = false
	hosting = false
	disconnected_pause = false
	latest.clear()
	next_command = 1
	session_id = ""
	connection_changed.emit()


func _process(delta: float) -> void:
	# Let the peer acknowledge a deliberate leave before closing TCP. Immediate
	# disconnect can discard the last packet and look like a connection loss.
	for retired: Dictionary in retiring_channels.duplicate():
		var channel: CityTcpChannel = retired.channel
		var streams: Array = retired.get("streams", [])
		if not streams.is_empty():
			if streams[0].pump(channel):
				streams.pop_front()
		elif not retired.get("ack_only", false) and not retired.get("sent_leave", false):
			channel.send({"type": "leave"})
			retired.sent_leave = true
		for message: Dictionary in channel.poll():
			if message.get("type") == "leave_ack":
				channel.failed = true
		if channel.failed or Time.get_ticks_msec() >= retired.until or (retired.get("ack_only", false) and channel.output.is_empty()):
			for stream: MultiplayerStateStream in streams:
				stream.close()
			channel.close()
			retiring_channels.erase(retired)
	if not active:
		return
	pump_wire_jobs()
	if not hosting and channels.is_empty() and reconnect_until > Time.get_ticks_msec() and Time.get_ticks_msec() >= reconnect_at:
		reconnect_attempt += 1
		reconnect_at = Time.get_ticks_msec() + mini(8000, 1000 * reconnect_attempt)
		join(reconnect_endpoint.address, reconnect_endpoint.port, reconnect_endpoint.code, reconnect_endpoint.name, reconnect_endpoint.intent)
	if hosting and server.is_connection_available():
		var peer := server.take_connection()
		if channels.size() >= MAX_PLAYERS - 1:
			peer.disconnect_from_host()
		else:
			channels[next_peer] = CityTcpChannel.new(peer, 65536)
			handshake_started[next_peer] = Time.get_ticks_msec()
			next_peer += 1
	for id: int in channels.keys():
		var channel := channels[id]
		var inbox: Array = received_messages.get(id, [])
		# Leave excess complete frames in the bounded transport input. Never drop
		# reliable commands, and bound execution as well as JSON parsing.
		if inbox.size() < 32:
			inbox.append_array(channel.poll(8 if hosting else 16))
		var began := Time.get_ticks_usec()
		while not inbox.is_empty() and not channel.failed:
			var index := 0
			if not hosting and decode_job != null:
				index = -1
				for candidate in inbox.size():
					if inbox[candidate].get("type") in ["result", "ping", "presence", "environment", "chat", "player_event", "action_audio"]:
						index = candidate
						break
				if index < 0:
					break
			var message: Dictionary = inbox[index]
			inbox.remove_at(index)
			if hosting:
				receive_host(id, message)
			else:
				receive_client(message)
			if Time.get_ticks_usec() - began >= 2000:
				break
		received_messages[id] = inbox
		if hosting and not identities.has(id) and not seats.pending.has(id) and Time.get_ticks_msec() - handshake_started.get(id, 0) > 10000:
			channel.failed = true
		if channel.failed:
			drop(id)
	heartbeat_elapsed += delta
	if heartbeat_elapsed >= 2.0:
		heartbeat_elapsed = 0.0
		for channel in channels.values():
			channel.send({"type": "ping"})
	if hosting:
		if not waiting_for_start:
			goal.advance(world, delta)
			if world is SharedWorld:
				loans.advance(world)
		if not waiting_for_start and goal.evaluate(world, members, loans):
			apply_speed()
			publish()
		snapshot_elapsed += delta
		if (snapshot_elapsed >= 0.25 and (published_revision != world.revision or published_policy != world.policy_revision)) or (build_publication_pending and Time.get_ticks_msec() >= build_publication_due):
			publish()
		environment_elapsed += delta
		if environment_elapsed >= 0.1 and environment_source.is_valid():
			var atmosphere: Dictionary = environment_source.call()
			var signature := atmosphere.duplicate()
			signature.erase("day_phase")
			signature.erase("season_phase")
			if signature != environment_signature or environment_elapsed >= 5.0:
				environment_elapsed = 0.0
				environment_signature = signature
				for id: int in identities:
					channels[id].send_latest({"type": "environment", "weather": atmosphere})
	presence_elapsed += delta
	if presence_elapsed >= 0.1:
		presence_elapsed = 0.0
		if not hosting and connected and interest_source.is_valid():
			var view: Dictionary = interest_source.call()
			if not view.is_empty() and view != interest_signature:
				interest_signature = view.duplicate(true)
				channels[0].send_latest({"type": "interest", "view": view})
		if cursor_source.is_valid():
			var position: Vector2 = cursor_source.call()
			var tool := MultiplayerCursor.valid_tool(cursor_tool_source.call() if cursor_tool_source.is_valid() else {})
			var selection: Array = selection_source.call() if selection_source.is_valid() else []
			if hosting:
				selections[token] = selection
				cursors[token] = [position.x, position.y]
				cursor_tools[token] = tool
				cursor_updated[token] = Time.get_ticks_msec()
			elif connected:
				var cursor := {"type": "cursor", "position": [position.x, position.y], "selection": selection, "tool": tool}
				if cursor != cursor_signature or Time.get_ticks_msec() - cursor_sent_at >= 1000:
					cursor_signature = cursor.duplicate(true)
					cursor_sent_at = Time.get_ticks_msec()
					channels[0].send_latest(cursor)
		if hosting:
			var players := presence_rows()
			presence_received.emit(merge_presence(players))
			if players != presence_signature:
				presence_signature = players.duplicate(true)
				for id: int in identities:
					channels[id].send_latest({"type": "presence", "players": players})
	# Prepare at least one recipient, then yield before another expensive city.
	# A slow recipient is skipped; its next state uses the newest authoritative data.
	var publication_started := Time.get_ticks_usec()
	for id: int in pending_publications.keys():
		if not identities.has(id):
			pending_publications.erase(id)
			continue
		if wire_jobs.has(id) or outgoing_states.has(id) or channels[id].output.size() >= CityTcpChannel.IO_BUDGET:
			continue
		var actor: String = identities[id]
		var viewed: String = viewed_cities.get(actor, actor)
		if not interest.due(world, actor, viewed, Time.get_ticks_msec()):
			continue
		send_state(id, make_state(actor))
		pending_publications.erase(id)
		if Time.get_ticks_usec() - publication_started >= 2000:
			break
	for id: int in outgoing_states.keys():
		if outgoing_states[id].pump(channels[id]):
			outgoing_states.erase(id)
	for channel in channels.values():
		channel.flush()


func receive_host(id: int, message: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	# TCP can deliver queued traffic in a burst after a temporary stall.
	var rate: Array = command_rates.get(id, [now, 512.0])
	rate[1] = minf(512.0, float(rate[1]) + maxf(0.0, now - int(rate[0])) * 0.128) - 1.0
	rate[0] = now
	command_rates[id] = rate
	if rate[1] < 0.0:
		channels[id].failed = true
		return
	if message.get("type") == "ping":
		return
	if not identities.has(id):
		if seats.pending.has(id):
			if message.get("type") == "seat_choice":
				seats.choose(id, message.get("seat"), message.get("city_name", ""))
			elif message.get("type") == "leave":
				channels[id].failed = true
			return
		if (message.get("type") != "hello" or message.get("protocol") != PROTOCOL
				or message.get("build") != NETWORK_BUILD or message.get("code") != code
				or not message.get("token") is String or message.token.length() != 48
				or not message.get("name") is String or message.name.strip_edges().is_empty()
				or message.name.length() > 32):
			channels[id].failed = true
			return
		if message.get("session", "") != "" and message.session != session_id:
			seats.reject(id, "This is a different session. Leave before joining it.")
			return
		seats.hello(id, message)
		return
	var actor: String = identities[id]
	if message.get("type") == "interest":
		if not interest.receive(actor, message.get("view"), world.city.map_size):
			channels[id].failed = true
		else:
			pending_publications[id] = true
		return
	if message.get("type") == "leave":
		graceful_peers[id] = true
		channels[id].send({"type": "leave_ack"})
		channels[id].flush()
		channels[id].failed = true
		return
	if message.get("type") == "cursor":
		var position: Variant = message.get("position")
		if position is Array and position.size() == 2 and valid_cursor_number(position[0]) and valid_cursor_number(position[1]):
			selections[actor] = valid_selection(message.get("selection", []), world.city.map_size)
			cursors[actor] = position
			cursor_tools[actor] = MultiplayerCursor.valid_tool(message.get("tool", {}))
			cursor_updated[actor] = Time.get_ticks_msec()
		return
	if message.get("type") == "resync":
		if wire_jobs.has(id):
			wire_jobs[id].finish()
			wire_jobs.erase(id)
		encoders.erase(id)
		if not outgoing_states.has(id):
			send_state(id, make_state(actor))
		else:
			pending_publications[id] = true
		return
	if message.get("type") == "chat":
		accept_chat(actor, message.get("text"))
		return
	if message.get("type") != "command":
		channels[id].failed = true
		return
	var response := execute(identities[id], message)
	interest.forced[actor] = true
	response["id"] = message.get("id", 0)
	channels[id].send(response)
	# Acknowledge now. Consecutive brush actions share one bounded publication.
	channels[id].flush()
	if message.get("kind") == "build":
		schedule_build_publication()
	else:
		publish()


func execute(actor: String, message: Dictionary) -> Dictionary:
	# A reliable ordered brush stream may depend on its own preceding edits
	# before their shared snapshot arrives. Never advance across another actor,
	# a simulation revision, a policy change or a city-view change.
	var before := world.revision
	var seen: Variant = message.get("revision")
	var build: bool = message.get("kind") == "build"
	var chained: bool = build and CoopWorld.whole_number(seen, 0, before) and build_chain.get("actor") == actor and build_chain.get("world") == world.get_instance_id() and build_chain.get("head") == before and int(seen) >= int(build_chain.get("base", before)) and message.get("view_owner", "") == build_chain.get("view", "")
	if chained:
		message = message.duplicate()
		message.revision = before
	var result := execute_ordered(actor, message)
	if result.get("ok", false) and build:
		build_chain = {"actor": actor, "world": world.get_instance_id(), "head": world.revision,
			"base": build_chain.base if chained else before, "view": message.get("view_owner", "")}
	elif not build or world.revision != before:
		build_chain.clear()
	result["revision"] = world.revision
	return result


func execute_ordered(actor: String, message: Dictionary) -> Dictionary:
	var member: Dictionary = members[actor]
	if not CoopWorld.whole_number(message.get("id"), 1, 2147483647):
		return CoopWorld.rejected("Invalid command identifier.")
	var sequence := int(message.id)
	if sequence <= int(member.sequence):
		return CoopWorld.rejected("This command was already handled; it was not applied again.")
	if sequence != int(member.sequence) + 1:
		return CoopWorld.rejected("Command order changed. Reconnect to synchronize.")
	member.sequence = sequence
	var result: Dictionary
	if message.get("kind") == "handicap":
		if actor != token or not waiting_for_start or not world is SharedWorld or starts.assigned:
			return CoopWorld.rejected("Only the host can assign handicaps before a new game starts.")
		var seat := seats.find_seat(str(message.get("seat", "")))
		if seat.is_empty() or not CoopWorld.whole_number(message.get("funds"), 0, 2147483647) or not CoopWorld.whole_number(message.get("tiles"), 0, world.city.map_size * world.city.map_size / 32):
			return CoopWorld.rejected("Invalid starting handicap.")
		var old: Dictionary = starts.handicaps.get(seat, {"funds": world.municipalities[seat].city.funds(), "tiles": 0})
		if not CoopWorld.whole_number(message.get("scale", 100), 50, 150) or int(message.get("scale", 100)) not in [50, 75, 100, 125, 150]:
			return CoopWorld.rejected("Invalid starting handicap.")
		starts.handicaps[seat] = {"funds": int(message.funds), "tiles": int(message.tiles), "scale": int(message.get("scale", 100))}
		reset_lobby_ready()
		if int(old.funds) != int(message.funds):
			announce_admin(actor, members[seat].name, "Starting funds", str(old.funds), str(message.funds))
		if old.get("tiles", 0) != message.tiles or old.get("scale", 100) != message.get("scale", 100):
			announce_admin(actor, members[seat].name, "Starting territory", "", str(message.tiles) if int(message.tiles) > 0 else str(message.get("scale", 100)) + "%")
		return CoopWorld.accepted("Starting handicap updated. Everyone must confirm Ready again.")
	if message.get("kind") == "lobby_ready":
		if not waiting_for_start or not message.get("ready") is bool or message.get("lobby_generation") != lobby_generation:
			return CoopWorld.rejected("Readiness can only be changed in the lobby.")
		lobby_ready[actor] = message.ready
		return CoopWorld.accepted("Readiness updated.")
	if message.get("kind") == "lobby_start":
		if actor != token or not can_start_lobby() or message.get("lobby_generation") != lobby_generation:
			return CoopWorld.rejected("Only the host can start when all connected players are ready.")
		if world is SharedWorld:
			if not starts.assigned and goal.kind != "endless":
				for tile in world.city.buildings.size():
					if world.city.buildings[tile] > 13 or world.city.zones[tile] != 0:
						return CoopWorld.rejected("Scored competitions require undeveloped starting terrain. Create a new city.")
			var start_error := starts.prepare(world, members)
			if not start_error.is_empty():
				return CoopWorld.rejected(start_error)
		goal.begin(world)
		waiting_for_start = false
		disconnected_pause = false
		for player: String in requested_speed:
			requested_speed[player] = 2
		apply_speed()
		return CoopWorld.accepted("The game has started.")
	if message.get("kind") == "rename_city":
		if not waiting_for_start or not message.get("name") is String or message.name.strip_edges().is_empty() or message.name.length() > Sc2xMetadata.MAX_NAME_CODE_POINTS:
			return CoopWorld.rejected("City names can only be changed in the lobby.")
		var municipality: CoopWorld = world.municipalities[actor] if world is SharedWorld else world
		municipality.city.document.set_city_name(message.name.strip_edges())
		municipality.revision += 1
		if municipality != world:
			world.revision += 1
		statistics_cache.clear()
		reset_lobby_ready()
		return CoopWorld.accepted("City name updated.")
	if waiting_for_start:
		return CoopWorld.rejected("Wait until the host starts the game.")
	if message.get("kind") == "view_city" and world is RegionWorld:
		var viewed := seats.find_seat(str(message.get("seat", "")))
		if viewed.is_empty():
			return CoopWorld.rejected("This city is not available.")
		viewed_cities[actor] = viewed
		return CoopWorld.accepted("City view changed.")
	if message.get("kind") == "rematch":
		return prepare_rematch(actor)
	if message.get("kind") == "continue_unscored":
		if actor != token or not goal.blocked():
			return CoopWorld.rejected("Only the host can continue the completed game without scoring.")
		goal.unscored = true
		apply_speed()
		return CoopWorld.accepted("The game continues without scoring.")
	if world is RegionWorld and viewed_cities.get(actor, actor) != actor and message.get("kind") not in ["speed"]:
		return CoopWorld.rejected("This city view is read-only. Return to your own city to make changes.")
	if message.get("kind") == "debug":
		return MultiplayerDebug.execute(self, actor, message)
	if goal.blocked() and message.get("kind") != "speed":
		return CoopWorld.rejected("The victory target was reached. The host can continue without scoring.")
	if actor != token and (message.get("kind") in ["disaster", "no_disasters"] or (message.get("kind") == "city_option" and message.get("option") == "no_disasters")):
		return CoopWorld.rejected("Only the host can control disasters.")
	if str(message.get("kind", "")).begins_with("loan_"):
		if not world is SharedWorld:
			return CoopWorld.rejected("Player loans require separate city finances.")
		return loans.command(world, actor, message)
	if message.get("kind") == "speed":
		if actor != token:
			return CoopWorld.rejected("Only the host can change the game speed.")
		if not CoopWorld.whole_number(message.get("speed"), 1, 5):
			return CoopWorld.rejected("Invalid speed.")
		requested_speed[actor] = int(message.speed)
		disconnected_pause = false
		apply_speed()
		result = CoopWorld.accepted("Your requested speed was updated.")
	else:
		if world is RegionWorld:
			var viewed: String = viewed_cities.get(actor, actor)
			if message.has("view_owner") and message.view_owner != viewed.sha256_text():
				return CoopWorld.rejected("Your city view changed. Review the target before acting.")
			message["view_owner"] = viewed.sha256_text()
		var admin_city: CoopWorld = world.municipalities[actor] if world is SharedWorld else world
		var before_admin := str(admin_city.engine.active_disaster_type) if message.get("kind") == "disaster" else str(admin_city.city.no_disasters_enabled())
		result = world.command(actor, message)
		if result.get("ok", false) and actor == token and (message.get("kind") in ["disaster", "no_disasters"] or (message.get("kind") == "city_option" and message.get("option") == "no_disasters")):
			var after_admin := str(admin_city.engine.active_disaster_type) if message.get("kind") == "disaster" else str(admin_city.city.no_disasters_enabled())
			announce_admin(actor, admin_city.city.city_name(), "Disaster administration", before_admin, after_admin)
		if goal.evaluate(world, members, loans):
			apply_speed()
	result["id"] = sequence
	announce_action(actor, message, result)
	return result


func apply_speed() -> void:
	var speed := int(requested_speed.get(token, GameSpeedController.Speed.PAUSED))
	world.controller.set_speed(1 if waiting_for_start else speed)
	if world is SharedWorld:
		world.set_shared_speed(1 if waiting_for_start else speed)


func can_start_lobby() -> bool:
	if not waiting_for_start or requested_speed.size() < 2 or not seats.pending.is_empty() or identities.size() != channels.size():
		return false
	for actor: String in requested_speed:
		if not lobby_ready.get(actor, false):
			return false
	return true


func reset_lobby_ready() -> void:
	if waiting_for_start:
		lobby_ready.clear()
		lobby_generation += 1


func release_disconnect_pause() -> void:
	if hosting:
		disconnected_pause = false
		apply_speed()
		publish()


func request(command: Dictionary) -> void:
	if not connected:
		feedback.emit("Disconnected. Reconnect before making changes.")
		return
	command["type"] = "command"
	command["id"] = next_command
	command["revision"] = command.get("revision", local_revision)
	command["policy"] = command.get("policy", local_policy)
	command["lobby_generation"] = latest.get("lobby", {}).get("generation", -1)
	if latest.get("mode") == "region":
		command["view_owner"] = latest.get("view_owner", "")
	next_command += 1
	command_started[int(command.id)] = Time.get_ticks_usec()
	if command_started.size() > 1024:
		command_started.erase(command_started.keys()[0])
	command_sent.emit(int(command.id), command)
	if hosting:
		var result := execute(token, command)
		play_result_sounds(result, int(command.id))
		resolve_command(int(command.id), result)
		feedback.emit(str(result.message))
		if result.has("choices"):
			choice_requested.emit(result)
		if command.get("kind") == "build":
			schedule_build_publication()
		else:
			publish()
	else:
		channels[0].send(command)
		channels[0].flush()


func receive_client(message: Dictionary, decoded := false) -> void:
	match message.get("type"):
		"packed_state":
			decode_job = MultiplayerWireJob.new()
			decode_job.start_state(message, decoder, true)
		"state_begin", "state_part", "state_end":
			if incoming_state == null:
				incoming_state = MultiplayerStateStream.new()
			var state := incoming_state.receive(message)
			if incoming_state.failed:
				channels[0].failed = true
				incoming_state.close()
			elif incoming_state.complete:
				incoming_state = null
				receive_client(state)
		"welcome":
			if not message.get("session") is String or not CoopWorld.whole_number(message.get("next"), 1, 2147483647):
				channels[0].failed = true
				return
			if not message.get("actor") is String or message.actor.length() != 48:
				channels[0].failed = true
				return
			token = message.actor
			session_id = message.session
			next_command = int(message.next)
		"seat_lobby":
			if message.get("seats") is Array:
				seat_lobby_received.emit(message)
		"state", "state_delta":
			if message.get("ended_copy") is String:
				var document := Sc2File.new()
				if document.parse(Marshalls.base64_to_raw(message.ended_copy)) and document.is_sc2x():
					ended_city = message.ended_copy
				return
			if not decoded and (message.has("wire_id") or message.get("type") == "state_delta"):
				decode_job = MultiplayerWireJob.new()
				decode_job.start_state(message, decoder, true)
				return
			if (not message.get("city") is String and not message.get("document") is Dictionary) or not CoopWorld.whole_number(message.get("revision"), 0, 9007199254740991):
				channels[0].failed = true
				return
			connected = true
			resync_requested = false
			reconnect_until = 0
			reconnect_attempt = 0
			accept_state(message)
		"action_audio":
			if message.get("event") is Dictionary:
				remote_action_sound.emit(message.event)
		"environment":
			if message.get("weather") is Dictionary:
				environment_received.emit(message.weather)
		"result":
			play_result_sounds(message, int(message.get("id", 0)))
			resolve_command(int(message.get("id", 0)), message)
			feedback.emit(str(message.get("message", "")))
			if message.get("choices") is Array and message.get("request") is Dictionary:
				choice_requested.emit(message)
		"chat":
			if message.get("message") is Dictionary:
				chat_received.emit(message.message)
		"player_event":
			if message.get("event") is Dictionary:
				player_event.emit(message.event)
		"ending":
			graceful_peers[0] = true
			reconnect_until = 0
		"leave":
			graceful_peers[0] = true
			channels[0].send({"type": "leave_ack"})
			channels[0].flush()
			channels[0].failed = true
		"summary":
			if message.get("values") is Dictionary and CoopWorld.whole_number(message.get("sequence"), 0, 9007199254740991) and int(message.sequence) >= int(latest.get("summary_sequence", -1)):
				for field: String in SUMMARY_FIELDS:
					if message.values.has(field):
						latest[field] = message.values[field]
				latest["summary_sequence"] = int(message.sequence)
				summary_received.emit(message.values)
		"presence":
			if message.get("players") is Array:
				presence_received.emit(merge_presence(message.players))
		"ping":
			pass
		"leave_ack":
			pass
		_:
			channels[0].failed = true


func resolve_command(id: int, result: Dictionary) -> void:
	if command_started.has(id):
		acknowledgement_usec.append(Time.get_ticks_usec() - int(command_started[id]))
		command_started.erase(id)
		if acknowledgement_usec.size() > 512:
			acknowledgement_usec.pop_front()
	command_resolved.emit(id, result)
	command_completed.emit(id)


func make_state(recipient := "") -> Dictionary:
	var state: Dictionary
	var actor := recipient if not recipient.is_empty() else token
	if world is RegionWorld:
		state = world.snapshot_region(actor, viewed_cities.get(actor, actor), true)
	else:
		state = world.snapshot_for(actor, true) if world is SharedWorld else world.snapshot(false, true)
	if common_state.is_empty() or common_revision != world.revision:
		common_state = make_common_state()
		common_revision = world.revision
	return state.merged(common_state)


func make_common_state() -> Dictionary:
	var state := {"summary_sequence": publication_count}
	if waiting_for_start and world is SharedWorld:
		if not starts.prepare(world, members, false).is_empty():
			starts.preview.clear()
	state["goal"] = goal.saved()
	state["loans"] = loans.public_rows()
	state["starts"] = starts.public_positions()
	state["round"] = starts.round_number
	state["lobby"] = {"waiting": waiting_for_start, "can_start": can_start_lobby(), "generation": lobby_generation}
	state["start_preview"] = starts.preview.duplicate(true)
	var players: Array[String] = []
	for player: String in requested_speed:
		players.append("%s (%s)" % [members[player].name, "paused" if requested_speed[player] == 1 else "playing"])
	state["players"] = players
	state["roster"] = roster()
	if not waiting_for_start:
		history.sample(world, state.roster)
	state["history"] = history.series.duplicate(true)
	if world is SharedWorld and not world is RegionWorld:
		state["offers"] = []
		for key: String in world.offers:
			state.offers.append(public_land_entry(world.offers[key].merged({"id": key, "status": "Open"}, true)))
		state["land_history"] = world.land_history.map(public_land_entry)
	state["admin_history"] = admin_history.duplicate(true)
	state["disconnect_pause"] = disconnected_pause
	return state


func schedule_build_publication() -> void:
	if not build_publication_pending:
		build_publication_due = Time.get_ticks_msec() + 40
	build_publication_pending = true


func publish() -> void:
	var started := Time.get_ticks_usec()
	common_state.clear()
	published_revision = world.revision
	published_policy = world.policy_revision
	build_publication_pending = false
	snapshot_elapsed = 0.0
	publication_count += 1
	var state := make_state()
	if not state.has("city") and not state.has("document"):
		feedback.emit(str(state.get("error", "Cannot synchronize the city.")))
		return
	accept_state(state)
	publication_usec += Time.get_ticks_usec() - started
	var summary := {}
	for field: String in SUMMARY_FIELDS:
		if state.has(field) and state[field] != summary_signature.get(field):
			summary[field] = state[field]
	summary_signature.merge(summary, true)
	for id: int in identities:
		pending_publications[id] = true
		if not summary.is_empty():
			channels[id].send_latest({"type": "summary", "sequence": publication_count, "values": summary})


func accept_state(state: Dictionary) -> void:
	if int(state.get("summary_sequence", -1)) < int(latest.get("summary_sequence", -1)):
		state = state.duplicate()
		for field: String in SUMMARY_FIELDS:
			if latest.has(field):
				state[field] = latest[field]
		state["summary_sequence"] = latest.summary_sequence
	if not state.get("visiting", false):
		confirmed_own_city = str(state.get("city", ""))
		confirmed_own_state = state.duplicate(true)
	latest = state
	local_revision = int(state.revision)
	local_policy = int(state.get("policy", 0))
	state_received.emit(state)
	if not hosting and state.get("weather") is Dictionary:
		environment_received.emit(state.weather)


func drop(id: int) -> void:
	if wire_jobs.has(id):
		wire_jobs[id].finish()
		wire_jobs.erase(id)
	if not hosting and decode_job != null:
		decode_job.finish()
		decode_job = null
	pending_publications.erase(id)
	received_messages.erase(id)
	encoders.erase(id)
	if outgoing_states.has(id):
		outgoing_states[id].close()
		outgoing_states.erase(id)
	if not hosting and incoming_state != null:
		incoming_state.close()
		incoming_state = null
	if graceful_peers.has(id) and not channels[id].output.is_empty():
		channels[id].failed = false
		channels[id].ephemeral.clear()
		retiring_channels.append({"channel": channels[id], "until": Time.get_ticks_msec() + 2000, "ack_only": true})
	else:
		channels[id].close()
	channels.erase(id)
	handshake_started.erase(id)
	command_rates.erase(id)
	seats.pending.erase(id)
	reset_lobby_ready()
	if hosting:
		if identities.has(id):
			var actor: String = identities[id]
			requested_speed.erase(actor)
			cursors.erase(actor)
			cursor_tools.erase(actor)
			cursor_updated.erase(actor)
			identities.erase(id)
			members[actor]["seat_status"] = "unoccupied" if graceful_peers.has(id) else "reserved"
			if not graceful_peers.has(id):
				disconnected_pause = false
			apply_speed()
			emit_player_event(actor, "left" if graceful_peers.has(id) else "disconnected")
	else:
		if graceful_peers.has(id):
			reconnect_until = 0
			session_ended.emit.call_deferred()
		elif connected and not reconnect_endpoint.is_empty():
			reconnect_until = Time.get_ticks_msec() + 90000
			reconnect_at = Time.get_ticks_msec() + 1000
		connected = false
		for member: Dictionary in latest.get("roster", []):
			if member.get("host", false):
				player_event.emit({"id": session_id + ":host-left", "name": member.name, "kind": "left" if graceful_peers.has(id) else "disconnected"})
		feedback.emit("The host ended the session." if graceful_peers.has(id) else "Connection lost or refused. Check host, port and password, then reconnect. The view is frozen.")
	graceful_peers.erase(id)
	if hosting:
		seats.refresh_lobbies()
		seats_changed.emit()
	connection_changed.emit()


func save_session(path: String) -> String:
	path = ProjectSettings.globalize_path(path)
	if not hosting:
		return "Only the host saves the shared session."
	var checkpoint_error := Sc2xCheckpoint.save_error(world.controller)
	if not checkpoint_error.is_empty():
		return checkpoint_error
	var data := {"format": "OpenSC2K Koop", "version": PROTOCOL, "build": BUILD,
		"started": not waiting_for_start,
		"admin_history": admin_history, "goal": goal.saved(), "loans": loans.saved(), "history": history.series, "starts": starts.saved(),
		"session": session_id, "host": token, "members": members, "seats": seats.saved(), "state": world.snapshot(true),
		"dispatch": Array(world.dispatch_cycles), "dispatch_initialized": world.dispatch_initialized,
		"dispatch_points": world.saved_dispatch_points(), "statistics": world.statistics, "dispatch_owners": world.dispatch_owners}
	if not data.state.has("city"):
		return str(data.state.get("error", "Cannot encode city."))
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write session: %s" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or not JSON.parse_string(FileAccess.get_file_as_string(temporary)) is Dictionary:
		return "The session could not be written and verified."
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return "Cannot replace the session backup."
		if DirAccess.rename_absolute(path, backup) != OK:
			return "Cannot preserve the previous session."
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return "Cannot install the new session file (%s). The previous save was retained." % error_string(rename_error)
	return ""


func resume_session(path: String, port: int, join_code: String, player_name: String) -> String:
	path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path).size() > CityTcpChannel.MAX_FRAME:
		return "The session file is missing or too large."
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version") != PROTOCOL or data.get("build") != BUILD or not data.get("state") is Dictionary:
		return "Unsupported session file."
	if not data.get("host") is String or not data.get("session") is String or not data.get("members") is Dictionary or not data.members.has(data.host):
		return "Invalid session identities."
	if not data.get("admin_history", []) is Array or data.get("admin_history", []).size() > 256:
		return "Invalid administration history."
	for entry: Variant in data.get("admin_history", []):
		if not entry is Dictionary:
			return "Invalid administration history."
		for field in ["id", "actor", "name", "color", "city", "action", "before", "after"]:
			if not entry.get(field) is String or entry[field].length() > 1024:
				return "Invalid administration history."
	var seat_error := MultiplayerSeats.validate(data.get("seats"), data.members)
	if not seat_error.is_empty():
		return seat_error
	for actor: Variant in data.members:
		var member: Variant = data.members[actor]
		if not actor is String or actor.length() != 48 or not member is Dictionary or not member.get("name") is String or not CoopWorld.whole_number(member.get("sequence"), 0, 2147483646):
			return "Invalid session member."
	if not data.state.get("city") is String:
		return "Missing session city."
	if not CoopWorld.whole_number(data.state.get("revision"), 0, 9007199254740990) or data.state.get("pending", "") != "":
		return "The session has no complete simulation checkpoint."
	if not data.get("dispatch") is Array or data.dispatch.size() != 3 or not data.get("dispatch_initialized") is bool:
		return "Invalid emergency service state."
	for value: Variant in data.dispatch:
		if not CoopWorld.whole_number(value, 0, 2147483647):
			return "Invalid emergency service cycle."
	var document := Sc2File.new()
	if not document.parse(Marshalls.base64_to_raw(data.state.city)):
		return document.parse_error
	var dispatch := CoopWorld.read_dispatch_points(data.get("dispatch_points"), document.map_size)
	if not dispatch.error.is_empty():
		return dispatch.error
	var host_error := host(document, port, join_code, player_name)
	if not host_error.is_empty():
		return host_error
	token = data.host
	session_id = data.session
	members = data.members
	requested_speed.clear()
	sounded_commands.clear()
	requested_speed[token] = 1
	next_command = int(members[token].sequence) + 1
	world.revision = int(data.state.get("revision", 0)) + 1
	world.tile_versions.fill(world.revision)
	world.dispatch_cycles = PackedInt32Array(data.dispatch)
	world.dispatch_initialized = data.dispatch_initialized
	world.dispatch_slot_points = dispatch.points
	world.statistics = data.get("statistics", {})
	world.dispatch_owners = data.get("dispatch_owners", {})
	seats.restore(data.get("seats"), player_name)
	waiting_for_start = data.get("started", true) != true
	reset_lobby_ready()
	apply_speed()
	next_command = int(members[token].sequence) + 1
	publish()
	return ""


static func valid_color(value: Variant) -> String:
	if value is String and value.length() == 6 and value.is_valid_hex_number(false):
		return value.to_lower()
	return "46b4ff"


func available_color(value: Variant) -> String:
	var wanted := valid_color(value)
	var used: Array = []
	for member: Dictionary in members.values():
		used.append(valid_color(member.get("color")))
	if not used.has(wanted):
		return wanted
	for color in ["ff9c40", "66cf79", "e77ba8", "c7a0ff", "ffe173", "62dbd4", "eeeeee", "b0bf5b"]:
		if not used.has(color):
			return color
	return wanted


func presence_rows() -> Array:
	var result: Array = []
	for actor: String in members:
		var member: Dictionary = members[actor]
		var fresh := Time.get_ticks_msec() - int(cursor_updated.get(actor, 0)) < 3000
		result.append({"id": actor.sha256_text(), "name": member.name, "color": valid_color(member.get("color")),
			"online": requested_speed.has(actor), "view_owner": str(viewed_cities.get(actor, actor)).sha256_text(),
			"selection": selections.get(actor, []) if fresh else [], "cursor_tool": cursor_tools.get(actor, {}),
			"cursor": cursors.get(actor, [-1, -1]) if fresh else [-1, -1]})
	return result


func merge_presence(rows: Array) -> Array:
	var result: Array = latest.get("roster", []).duplicate(true)
	for row: Variant in rows:
		if not row is Dictionary or not row.get("id") is String:
			continue
		for player: Dictionary in result:
			if player.get("id") == row.id:
				player.merge(row, true)
				break
	return result


func roster() -> Array:
	var result: Array = []
	if statistics_revision != world.revision:
		statistics_cache.clear()
		statistics_revision = world.revision
	for actor: String in members:
		var member: Dictionary = members[actor]
		if not statistics_cache.has(actor):
			statistics_cache[actor] = MultiplayerStatistics.capture(world, actor)
		var row: Dictionary = statistics_cache[actor].duplicate()
		row.debt = int(row.debt) + loans.debt(actor)
		if goal.kind == "timed_score":
			row["points"] = goal.final_scores.get(actor.sha256_text(), MultiplayerGoal.score_units(int(row.population), int(row.funds) - int(row.debt)))
		row["ranked"] = member.get("ranked", true)
		row["handicap"] = starts.handicaps.get(actor, {}).duplicate(true)
		row.merge({"id": actor.sha256_text(), "name": member.name, "host": actor == token,
			"ready": lobby_ready.get(actor, false),
			"color": valid_color(member.get("color")), "online": requested_speed.has(actor),
			"seat_status": "connected" if requested_speed.has(actor) else member.get("seat_status", "reserved"),
			"view_owner": str(viewed_cities.get(actor, actor)).sha256_text(),
			"selection": selections.get(actor, []) if Time.get_ticks_msec() - int(cursor_updated.get(actor, 0)) < 3000 else [],
			"cursor_tool": cursor_tools.get(actor, {}),
			"cursor": cursors.get(actor, [-1, -1]) if Time.get_ticks_msec() - int(cursor_updated.get(actor, 0)) < 3000 else [-1, -1]})
		result.append(row)
	return result


func broadcast(message: Dictionary) -> void:
	for id: int in identities:
		if channels[id].output.size() < CityTcpChannel.IO_BUDGET:
			channels[id].send(message)


func send_chat(text: String) -> void:
	if not connected:
		return
	if hosting:
		accept_chat(token, text)
	else:
		channels[0].send({"type": "chat", "text": text})
		channels[0].flush()


func accept_chat(actor: String, value: Variant) -> void:
	if not value is String or value.strip_edges().is_empty() or value.length() > 500:
		return
	var now := Time.get_ticks_msec()
	if now - int(chat_last_sent.get(actor, -1000)) < 500:
		return
	chat_last_sent[actor] = now
	event_sequence += 1
	var entry := {"id": session_id + ":" + str(event_sequence), "sender": actor.sha256_text(), "name": members[actor].name, "color": valid_color(members[actor].get("color")),
		"text": value.strip_edges(), "time": Time.get_datetime_string_from_system()}
	chat_history.append(entry)
	if chat_history.size() > 100:
		chat_history.pop_front()
	chat_received.emit(entry)
	for id: int in identities:
		channels[id].send({"type": "chat", "message": entry})


func city_checkpoint() -> Dictionary:
	if not hosting:
		return {"error": "Only the host saves the game."}
	var error := Sc2xCheckpoint.save_error(world.controller)
	if not error.is_empty():
		return {"error": error}
	Sc2xCheckpoint.capture(world.controller, world.city.document.sc2x_metadata)
	var document := world.city.document.duplicate_document()
	var data := {"version": 1, "host": token, "session": session_id, "members": members, "seats": seats.saved(),
		"started": not waiting_for_start,
		"admin_history": admin_history, "goal": goal.saved(), "loans": loans.saved(), "history": history.series, "starts": starts.saved(),
		"statistics": world.statistics, "dispatch_owners": world.dispatch_owners,
		"dispatch": Array(world.dispatch_cycles), "dispatch_initialized": world.dispatch_initialized, "dispatch_points": world.saved_dispatch_points()}
	if world is SharedWorld:
		data["shared"] = world.saved_shared()
		if data.shared.has("error"):
			return {"error": data.shared.error}
	document.sc2x_extra_entries["multiplayer.json"] = JSON.stringify(data).to_utf8_buffer()
	return {"error": "", "document": document}


func save_city(path: String) -> String:
	var checkpoint := city_checkpoint()
	if not checkpoint.error.is_empty():
		return checkpoint.error
	return write_document(checkpoint.document, path)


static func write_document(document: Sc2File, path: String) -> String:
	var encoded := Sc2xDocument.encode(document)
	if not encoded.ok:
		return encoded.error
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write the city."
	file.store_buffer(encoded.data)
	file.flush()
	var result := file.get_error()
	file.close()
	var check := Sc2File.new()
	if result != OK or not check.parse(FileAccess.get_file_as_bytes(temporary)):
		return "Cannot verify the saved city."
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return "Cannot replace the previous backup."
		if DirAccess.rename_absolute(path, backup) != OK:
			return "Cannot back up the previous city."
	if DirAccess.rename_absolute(temporary, path) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return "Cannot install the saved city; the previous save was retained."
	return ""


func restore_embedded(document: Sc2File) -> String:
	var data: Variant = JSON.parse_string(document.sc2x_extra_entries.get("multiplayer.json", PackedByteArray()).get_string_from_utf8())
	if not data is Dictionary or data.get("version") != 1 or not data.get("members") is Dictionary:
		return "Invalid multiplayer city data."
	if not data.get("host") is String or not data.members.has(data.host) or not data.get("session") is String:
		return "Invalid multiplayer identities."
	if not MultiplayerGoal.valid(data.get("goal"), document.map_size):
		return "Invalid saved victory goal."
	if not MultiplayerLoans.valid(data.get("loans", {"next": 1, "contracts": []}), data.members) or not MultiplayerHistory.valid(data.get("history", {}), data.members) or not MultiplayerStarts.valid(data.get("starts", {"round": 1, "assigned": true, "previous": {}, "positions": {}}), data.members, document.map_size):
		return "Invalid saved competition data."
	if not data.get("admin_history", []) is Array or data.get("admin_history", []).size() > 256:
		return "Invalid administration history."
	for entry: Variant in data.get("admin_history", []):
		if not entry is Dictionary:
			return "Invalid administration history."
		for field in ["id", "actor", "name", "color", "city", "action", "before", "after"]:
			if not entry.get(field) is String or entry[field].length() > 1024:
				return "Invalid administration history."
	var seat_error := MultiplayerSeats.validate(data.get("seats"), data.members)
	if not seat_error.is_empty():
		return seat_error
	for actor: Variant in data.members:
		var member: Variant = data.members[actor]
		if not actor is String or actor.length() != 48 or not member is Dictionary or not member.get("name") is String or not CoopWorld.whole_number(member.get("sequence"), 0, 2147483646):
			return "Invalid multiplayer member."
	if not data.get("dispatch") is Array or data.dispatch.size() != 3:
		return "Invalid dispatch state."
	for value: Variant in data.dispatch:
		if not CoopWorld.whole_number(value, 0, 2147483647):
			return "Invalid dispatch cycle."
	if not data.get("statistics") is Dictionary or not data.get("dispatch_owners") is Dictionary:
		return "Invalid multiplayer statistics."
	if data.has("shared") and not data.shared is Dictionary:
		return "Invalid multiplayer city data."
	var restored_world: CoopWorld = RegionWorld.new() if data.get("shared", {}).get("mode") == "region" else SharedWorld.new() if data.get("shared") is Dictionary else CoopWorld.new()
	if not restored_world.open(document):
		return restored_world.error
	if restored_world is SharedWorld:
		var shared_error: String = restored_world.restore_shared(data.shared)
		if not shared_error.is_empty():
			return shared_error
		if restored_world.host_actor != data.host or restored_world.actors.size() != data.members.size():
			return "Saved municipalities do not match session members."
		for actor: String in restored_world.actors:
			if not data.members.has(actor):
				return "Missing municipality member."
	var dispatch := CoopWorld.read_dispatch_points(data.get("dispatch_points", []), document.map_size)
	if not dispatch.error.is_empty():
		return dispatch.error
	restored_world.dispatch_slot_points = dispatch.points
	world = restored_world
	token = data.host
	session_id = data.session
	members = data.members
	requested_speed.clear()
	sounded_commands.clear()
	requested_speed[token] = 1
	next_command = int(members[token].sequence) + 1
	world.statistics = data.statistics
	world.dispatch_owners = data.dispatch_owners
	world.dispatch_cycles = PackedInt32Array(data.dispatch)
	world.dispatch_initialized = data.get("dispatch_initialized") == true
	ensure_credential()
	seats.restore(data.get("seats"), local_player_name)
	goal = MultiplayerGoal.new()
	goal.restore(data.get("goal"))
	loans = MultiplayerLoans.new()
	loans.contracts = data.get("loans", {}).get("contracts", []).duplicate(true)
	loans.next_id = int(data.get("loans", {}).get("next", 1))
	if world is SharedWorld:
		loans.migrate(world)
	history = MultiplayerHistory.new()
	history.series = data.get("history", {}).duplicate(true)
	admin_history = data.get("admin_history", []).duplicate(true)
	for entry: Dictionary in admin_history:
		event_sequence = maxi(event_sequence, int(str(entry.id).get_slice(":admin:", 1)))
	starts.restore(data.get("starts", {"round": 1, "assigned": true, "previous": {}, "positions": {}}))
	if world is SharedWorld:
		starts.repair_reserved_corridors(world)
	waiting_for_start = data.get("started", true) != true
	reset_lobby_ready()
	apply_speed()
	next_command = int(members[token].sequence) + 1
	publish()
	return ""


func valid_cursor_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= -1.0 and float(value) < world.city.map_size


func emit_player_event(actor: String, kind: String, excluded := -1) -> void:
	event_sequence += 1
	var event := {"id": session_id + ":" + str(event_sequence), "name": members[actor].name, "kind": kind}
	player_event.emit(event)
	for id: int in identities:
		if id != excluded:
			channels[id].send({"type": "player_event", "event": event})


func public_land_entry(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	result["name"] = members.get(record.get("seller", ""), {}).get("name", "")
	result["buyer_name"] = members.get(record.get("buyer", ""), {}).get("name", "")
	result["seller"] = str(record.get("seller", "")).sha256_text()
	result["buyer"] = str(record.buyer).sha256_text() if record.has("buyer") else ""
	result["count"] = record.get("tiles", []).size()
	result["awaiting"] = str(record.get("awaiting", record.get("seller") if record.has("buyer") else "")).sha256_text() if record.has("buyer") else ""
	result["initiator"] = str(record.get("initiator", record.get("buyer", record.get("seller", "")))).sha256_text()
	return result


func send_state(id: int, state: Dictionary) -> void:
	if wire_jobs.has(id) or outgoing_states.has(id):
		pending_publications[id] = true
		return
	if not encoders.has(id):
		encoders[id] = MultiplayerDelta.new()
	var encoder: MultiplayerDelta = encoders[id]
	var job := MultiplayerWireJob.new()
	job.start_state(state, encoder)
	wire_jobs[id] = job
	if identities.has(id):
		var actor: String = identities[id]
		interest.published(actor, viewed_cities.get(actor, actor), state, Time.get_ticks_msec())


func send_state_body(id: int, body: PackedByteArray) -> void:
	if body.size() < MultiplayerStateStream.CHUNK_BYTES:
		channels[id].send_encoded(body)
		return
	var stream := MultiplayerStateStream.new()
	if not stream.open_encoded(body):
		stream.close()
		feedback.emit("The city snapshot could not be prepared for transfer.")
		channels[id].failed = true
		return
	outgoing_states[id] = stream


func pump_wire_jobs() -> void:
	for id: int in wire_jobs.keys():
		var job: MultiplayerWireJob = wire_jobs[id]
		if not job.ready():
			continue
		job.finish()
		wire_jobs.erase(id)
		if channels.has(id):
			if job.failed:
				channels[id].failed = true
			else:
				send_state_body(id, job.bytes)
				if encoders.has(id):
					if job.full:
						encoders[id].full_bytes += job.bytes.size()
					else:
						encoders[id].delta_bytes += job.bytes.size()
	if decode_job != null and decode_job.ready():
		var job := decode_job
		decode_job = null
		job.finish()
		if job.failed:
			if channels.has(0):
				channels[0].failed = true
		elif job.baseline_failed:
			if not resync_requested and channels.has(0):
				channels[0].send({"type": "resync"})
				resync_requested = true
		else:
			receive_client(job.decoded, true)


func close_wire_jobs() -> void:
	for job: MultiplayerWireJob in wire_jobs.values():
		job.finish()
	wire_jobs.clear()
	if decode_job != null:
		decode_job.finish()
		decode_job = null


func prepare_rematch(actor: String) -> Dictionary:
	if actor != token or not world is SharedWorld or goal.winners.is_empty() or waiting_for_start:
		return CoopWorld.rejected("Only the host can propose a rematch after the result.")
	var candidate: SharedWorld = RegionWorld.new() if world is RegionWorld else SharedWorld.new()
	candidate.land_price = world.land_price
	candidate.starter_tiles = world.starter_tiles
	# Reuse the original terrain and difficulty, not the developed end-game city.
	if not candidate.open(world.template):
		return CoopWorld.rejected(candidate.error)
	for player: String in world.actors:
		var error := candidate.add_player(player)
		if not error.is_empty():
			return CoopWorld.rejected(error)
		candidate.municipalities[player].city.document.set_city_name(world.municipalities[player].city.city_name())
	var next_starts := MultiplayerStarts.new()
	next_starts.previous = starts.previous.duplicate(true)
	next_starts.handicaps = starts.handicaps.duplicate(true)
	next_starts.round_number = starts.round_number + 1
	var next_members := members.duplicate(true)
	var error := next_starts.prepare(candidate, next_members, false)
	if not error.is_empty():
		return CoopWorld.rejected(error)
	candidate.revision = world.revision + 1
	candidate.tile_versions.fill(candidate.revision)
	world = candidate
	members = next_members
	starts = next_starts
	loans = MultiplayerLoans.new()
	history = MultiplayerHistory.new()
	goal.reset_clock(world)
	goal.winners.clear()
	goal.holding.clear()
	goal.unscored = false
	statistics_cache.clear()
	statistics_revision = -1
	viewed_cities.clear()
	cursors.clear()
	cursor_tools.clear()
	selections.clear()
	waiting_for_start = true
	reset_lobby_ready()
	apply_speed()
	return CoopWorld.accepted("Rematch prepared with new starting positions. Everyone must confirm Ready again.")

func play_result_sounds(result: Dictionary, id: int) -> void:
	if not result.get("ok", false) or id <= 0 or sounded_commands.has(id):
		return
	sounded_commands[id] = true
	if sounded_commands.size() > 256:
		sounded_commands.erase(sounded_commands.keys()[0])
	var sounds: Array[int] = []
	if result.get("sounds") is Array:
		for value: Variant in result.sounds.slice(0, 32):
			if CoopWorld.whole_number(value, 500, 529):
				sounds.append(int(value))
	if not sounds.is_empty():
		action_sounds.emit(sounds)

func announce_action(actor: String, command: Dictionary, result: Dictionary) -> void:
	if not result.get("ok", false) or result.get("sounds", []).is_empty() or command.get("kind") not in ["build", "land_buy", "land_accept"]:
		return
	var point: Variant = result.get("sound_point", command.get("finish"))
	if not point is Array or point.size() != 2:
		return
	var event := {"actor": actor.sha256_text(), "id": command.id, "sounds": result.sounds,
		"point": point, "view_owner": command.get("view_owner", actor.sha256_text())}
	if actor != token:
		remote_action_sound.emit(event)
	for peer: int in identities:
		if identities[peer] != actor:
			channels[peer].send({"type": "action_audio", "event": event})


static func handicap_text(value: Dictionary) -> String:
	return "Funds: $%d · Start tiles: %d (0 = automatic)" % [value.funds, value.tiles]


func announce_admin(actor: String, city_name: String, action: String, before: String, after: String) -> void:
	event_sequence += 1
	admin_history.append({"id": session_id + ":admin:" + str(event_sequence), "actor": actor.sha256_text(), "name": members[actor].name, "color": valid_color(members[actor].get("color")), "city": city_name, "action": action, "before": before, "after": after})
	if admin_history.size() > 256:
		admin_history.pop_front()

static func valid_selection(value: Variant, size: int) -> Array:
	if not value is Array or value.size() > 1024:
		return []
	for point: Variant in value:
		if not point is Array or point.size() != 2 or not CoopWorld.whole_number(point[0], 0, size - 1) or not CoopWorld.whole_number(point[1], 0, size - 1):
			return []
	return value
