class_name MultiplayerConnectivity
extends VBoxContainer
## Local host diagnostics, never part of synchronized city state.

var session: CoopSession
var status: Label
var detail: Label
var retry: Button


func _init(owner: CoopSession) -> void:
	session = owner
	status = ApplicationMultiplayer.label(self, "")
	detail = ApplicationMultiplayer.label(self, "")
	retry = ApplicationMultiplayer.button(self, "Check again", func() -> void:
		if session.online != null:
			session.online.request_check())
	visible = false


func _process(_delta: float) -> void:
	visible = session.active and session.hosting and session.online != null
	if not visible or not is_visible_in_tree():
		return
	var online := session.online
	status.text = online.status_text()
	status.modulate = Color("66cf79") if online.reachability == "reachable" else Color("ffb35c") if online.reachability == "unreachable" else Color("b8c0cc")
	detail.text = online.mapping_text()
	retry.text = tr("Check again")
	retry.disabled = online.pending or online.check_requested or Time.get_ticks_msec() < online.check_after
