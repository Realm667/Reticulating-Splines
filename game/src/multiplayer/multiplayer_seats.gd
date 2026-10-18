class_name MultiplayerSeats
extends RefCounted
## Credentials identify people; stable actor keys identify saved city seats.
## Only the host changes this association. Credentials never enter public rosters.

var owner_ref: WeakRef
var session: CoopSession:
	get:
		return owner_ref.get_ref()
var credentials: Dictionary = {}
var pending: Dictionary = {}
var history: Array = []


func _init(owner: CoopSession) -> void:
	owner_ref = weakref(owner)


func clear() -> void:
	credentials.clear()
	pending.clear()
	history.clear()


func hello(peer: int, message: Dictionary) -> void:
	var identity: String = message.token
	var actor: String = credentials.get(identity.sha256_text(), "")
	if not actor.is_empty():
		if session.requested_speed.has(actor):
			reject(peer, "This player seat is already connected.")
			return
		session.members[actor].name = message.name
		session.members[actor].color = session.valid_color(message.get("color"))
		admit(peer, actor)
		return
	for other: int in pending:
		if pending[other].identity == identity:
			reject(peer, "This identity is already waiting to join.")
			return
	pending[peer] = {"identity": identity, "name": message.name, "color": message.get("color"), "seat": ""}
	session.reset_lobby_ready()
	if message.get("intent", "new") == "new":
		choose(peer, "new")
	else:
		send_lobby(peer)
	session.seats_changed.emit()


func choose(peer: int, choice: Variant, city_name: Variant = "") -> void:
	if not pending.has(peer) or not choice is String:
		return
	if choice == "new":
		if not city_name is String or city_name.length() > Sc2xMetadata.MAX_NAME_CODE_POINTS:
			reject(peer, "Invalid city name.", false)
			return
		if session.members.size() >= CoopSession.MAX_PLAYERS:
			reject(peer, "All player seats are occupied. Request an unoccupied seat instead.", false)
			return
		var actor := Crypto.new().generate_random_bytes(24).hex_encode()
		if session.world is SharedWorld:
			var error: String = session.world.add_player(actor)
			if not error.is_empty():
				reject(peer, error, false)
				return
			var name: String = city_name.strip_edges()
			if name.is_empty():
				name = str(pending[peer].name)
			session.world.municipalities[actor].city.document.set_city_name(name)
		var applicant: Dictionary = pending[peer]
		session.members[actor] = {"name": applicant.name, "sequence": 0,
			"color": session.valid_color(applicant.color), "seat_status": "connected", "ranked": session.waiting_for_start and not session.continuing}
		credentials[str(applicant.identity).sha256_text()] = actor
		admit(peer, actor)
		return
	var actor := find_seat(choice)
	if actor.is_empty() or session.requested_speed.has(actor):
		reject(peer, "This seat is no longer available.", false)
		return
	pending[peer].seat = actor
	send_lobby(peer)
	session.feedback.emit("%s requests the seat of %s." % [pending[peer].name, session.members[actor].name])
	session.seats_changed.emit()


func decide(peer: int, approve: bool) -> void:
	if not session.hosting or not pending.has(peer):
		return
	var actor: String = pending[peer].seat
	if actor.is_empty():
		return
	if not approve:
		pending[peer].seat = ""
		reject(peer, "The host declined the seat request.", false)
		session.seats_changed.emit()
		return
	if not session.members.has(actor) or session.requested_speed.has(actor):
		pending[peer].seat = ""
		reject(peer, "This seat is no longer available.", false)
		return
	var applicant: Dictionary = pending[peer]
	transfer(actor, applicant.identity, applicant.name, applicant.color)
	admit(peer, actor, "taken_over")
	refresh_lobbies()


func transfer(actor: String, identity: String, player_name: String, color: Variant) -> void:
	var own: CoopWorld = session.world.municipalities[actor] if session.world is SharedWorld else session.world
	history.append({"seat": actor.sha256_text(), "name": session.members[actor].name,
		"statistics": own.statistics.get(actor, {}).duplicate(true)})
	if history.size() > 256:
		history.pop_front()
	own.statistics.erase(actor)
	session.world.statistics.erase(actor)
	session.loans.contracts = session.loans.contracts.filter(func(loan: Dictionary) -> bool: return loan.status != "offered" or actor not in [loan.lender, loan.borrower])
	if session.world is SharedWorld:
		for key: String in session.world.offers.keys():
			var offer: Dictionary = session.world.offers[key]
			if offer.get("seller") == actor or offer.get("buyer") == actor:
				session.world.finish_land_entry(key, "Withdrawn")
		# Financial and city totals remain with the seat, including land spending.
	# A previous controller's undo snapshot must not undo the handover.
	own.undo_document = null
	for key: String in credentials.keys():
		if credentials[key] == actor:
			credentials.erase(key)
	credentials[identity.sha256_text()] = actor
	session.members[actor].name = player_name.left(32)
	session.members[actor].color = session.valid_color(color)
	session.statistics_cache.clear()
	session.world.revision += 1


func admit(peer: int, actor: String, kind := "joined") -> void:
	pending.erase(peer)
	session.identities[peer] = actor
	session.members[actor]["seat_status"] = "connected"
	session.requested_speed[actor] = 5
	session.reset_lobby_ready()
	session.apply_speed()
	# The host must see the same readiness generation as the newly admitted
	# guest before either can click Ready, independently of snapshot cadence.
	session.publish()
	session.channels[peer].send({"type": "welcome", "session": session.session_id,
		"actor": actor, "next": int(session.members[actor].sequence) + 1})
	if session.environment_source.is_valid():
		session.channels[peer].send_latest({"type": "environment", "weather": session.environment_source.call()})
	session.send_state(peer, session.make_state(actor))
	for item: Dictionary in session.chat_history:
		session.channels[peer].send({"type": "chat", "message": item.merged({"history": true}, true)})
	session.emit_player_event(actor, kind, peer if kind == "joined" else -1)
	session.seats_changed.emit()
	refresh_lobbies()


func find_seat(public_id: String) -> String:
	for actor: String in session.members:
		if actor.sha256_text() == public_id:
			return actor
	return ""


func send_lobby(peer: int) -> void:
	var rows: Array = []
	for row: Dictionary in session.roster():
		if not row.online:
			rows.append({"id": row.id, "name": row.name, "city": row.city,
				"status": row.get("seat_status", "unoccupied")})
	session.channels[peer].send({"type": "seat_lobby", "seats": rows,
		"shared": session.world is SharedWorld,
		"new_allowed": session.members.size() < CoopSession.MAX_PLAYERS,
		"waiting": not str(pending[peer].seat).is_empty()})


func refresh_lobbies() -> void:
	for peer: int in pending:
		if session.channels.has(peer):
			send_lobby(peer)


func reject(peer: int, message: String, close := true) -> void:
	session.channels[peer].send({"type": "result", "ok": false, "message": message})
	if close:
		session.channels[peer].flush()
		session.channels[peer].failed = true
	elif pending.has(peer):
		send_lobby(peer)


func saved() -> Dictionary:
	return {"version": 1, "credentials": credentials.duplicate(), "history": history.duplicate(true)}


static func validate(data: Variant, members: Dictionary) -> String:
	if data == null:
		return ""
	if not data is Dictionary or data.get("version") != 1 or not data.get("credentials") is Dictionary or not data.get("history") is Array:
		return "Invalid saved player seats."
	if data.credentials.size() > members.size() or data.history.size() > 256:
		return "Invalid saved player seats."
	var assigned: Array = []
	for key: Variant in data.credentials:
		var actor: Variant = data.credentials[key]
		if not key is String or key.length() != 64 or not key.is_valid_hex_number(false) or not actor is String or not members.has(actor) or assigned.has(actor):
			return "Invalid saved player seats."
		assigned.append(actor)
	for entry: Variant in data.history:
		if not entry is Dictionary or not entry.get("name") is String or not entry.get("seat") is String or not entry.get("statistics") is Dictionary:
			return "Invalid saved player seats."
	return ""


func restore(data: Variant, player_name: String) -> void:
	credentials.clear()
	if data == null:
		# Old versions used the private reconnect credential as the city key.
		for actor: String in session.members:
			credentials[actor.sha256_text()] = actor
		history = []
	else:
		credentials = data.credentials.duplicate()
		history = data.history.duplicate(true)
	for actor: String in session.members:
		if actor != session.token and session.members[actor].get("seat_status") != "unoccupied":
			session.members[actor]["seat_status"] = "reserved"
	# Loading the complete save explicitly grants its holder hosting authority.
	# Keep their personal credential; never overwrite it with the old host's.
	if credentials.get(session.credential.sha256_text()) != session.token:
		transfer(session.token, session.credential, player_name, session.player_color)
	session.members[session.token]["seat_status"] = "connected"
