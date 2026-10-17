extends SceneTree

class RouterMapping extends MultiplayerPortMapping:
	func discover_gateway() -> UPNPDevice:
		var gateway := UPNPDevice.new()
		gateway.igd_status = UPNPDevice.IGD_STATUS_OK
		gateway.igd_our_addr = "127.0.0.1"
		gateway.igd_service_type = "urn:schemas-upnp-org:service:WANIPConnection:1"
		gateway.igd_control_url = MultiplayerOnline.base_url() + "/upnp/control"
		return gateway

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func wait_idle(mapping: MultiplayerPortMapping) -> void:
	var until := Time.get_ticks_msec() + 8000
	while is_instance_valid(mapping) and mapping.worker != null and Time.get_ticks_msec() < until:
		await process_frame


func run() -> void:
	assert(MultiplayerOnline.base_url().begins_with("http://127.0.0.1:"))
	var first := RouterMapping.new()
	root.add_child(first)
	first.start(20000)
	await wait_idle(first)
	check(first.owned and first.state == "mapped", "real UPnPDevice creates bounded TCP lease via SOAP")
	var second := RouterMapping.new()
	root.add_child(second)
	second.start(20000)
	await wait_idle(second)
	check(not second.owned and second.state == "existing", "existing mapping is not replaced")
	second.finish()
	await process_frame
	first.launch("renew")
	await wait_idle(first)
	check(first.owned and first.state == "mapped", "own lease renews")
	first.finish()
	await wait_idle(first)
	await process_frame
	var third := RouterMapping.new()
	root.add_child(third)
	third.start(20000)
	await wait_idle(third)
	check(third.owned, "normal leave removed own mapping")
	third.marker = "different-owner"
	third.launch("renew")
	await wait_idle(third)
	check(not third.owned, "ownership change prevents renew or deletion")
	third.finish()
	await process_frame
	var cancelled := RouterMapping.new()
	root.add_child(cancelled)
	cancelled.start(20001)
	cancelled.finish()
	await wait_idle(cancelled)
	await process_frame
	var replacement := RouterMapping.new()
	root.add_child(replacement)
	replacement.start(20001)
	await wait_idle(replacement)
	check(replacement.owned, "leave during discovery cleans mapping after worker completes")
	replacement.finish()
	await wait_idle(replacement)
	await process_frame
	var session := CoopSession.new()
	root.add_child(session)
	var online := MultiplayerOnline.new()
	session.add_child(online)
	online.session = session
	online.mapping = RouterMapping.new()
	online.add_child(online.mapping)
	online.mapping.start(20002)
	var retired: WeakRef = weakref(online.mapping)
	online.finish()
	var deadline := Time.get_ticks_msec() + 8000
	while retired.get_ref() != null and Time.get_ticks_msec() < deadline:
		await process_frame
	check(retired.get_ref() == null, "router cleanup outlives directory removal and finishes asynchronously")
	var after_leave := RouterMapping.new()
	root.add_child(after_leave)
	after_leave.start(20002)
	await wait_idle(after_leave)
	check(after_leave.owned, "online leave removes mapping even during its creation")
	after_leave.finish()
	await wait_idle(after_leave)
	session.queue_free()
	await process_frame
	print("UPnP integration: %d failure(s)" % failures)
	quit(1 if failures else 0)
