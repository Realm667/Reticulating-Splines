class_name MultiplayerCompetitionWindows
extends RefCounted

var owner_ref: WeakRef
var windows: MultiplayerWindows:
	get:
		return owner_ref.get_ref()
var ending: Window
var end_rows: VBoxContainer
var end_scores := MultiplayerScoreboard.new()
var result_label: Label
var continue_button: Button
var rematch_button: Button
var won_key := ""
var firework_started := 0
var firework_point := Vector2i.ZERO
var fireworks_audio: AudioStreamPlayer
var last_burst := -1
var previous_music := -1

func _init(owner: MultiplayerWindows) -> void:
	owner_ref = weakref(owner)
	fireworks_audio = AudioStreamPlayer.new()
	fireworks_audio.max_polyphony = 4
	fireworks_audio.stream = firework_sound()
	windows.coop.app.add_child(fireworks_audio)
	ending = windows.make_window("Victory")
	ending.size = Vector2i(1000, 400)
	end_rows = windows.content(ending)
	ending.visibility_changed.connect(func() -> void:
		if not ending.visible:
			restore_music()
		if is_instance_valid(windows.chat):
			windows.dock_chat(windows.start_lobby.window.visible))
	result_label = ApplicationMultiplayer.label(end_rows, "")
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_scores.setup(end_rows)
	end_rows.minimum_size_changed.connect(func() -> void: windows.fit_content.call_deferred(ending, end_rows, 1000))
	var actions := HBoxContainer.new()
	end_rows.add_child(actions)
	ApplicationMultiplayer.button(actions, "Leave game", windows.coop.confirm_leave)
	continue_button = ApplicationMultiplayer.button(actions, "Continue without scoring (endless)", func() -> void:
		windows.coop.session.request({"kind": "continue_unscored"}))

	rematch_button = ApplicationMultiplayer.button(actions, "Rematch · rotate starts", func() -> void:
		windows.coop.session.request({"kind": "rematch"}))

func open_regions() -> void:
	windows.coop.app.regions.open_overview()

func update(state: Dictionary) -> void:
	var goal: Dictionary = state.get("goal", {})
	var winners: Array = goal.get("winners", [])
	if winners.is_empty() or goal.get("unscored", false):
		ending.hide()
		if winners.is_empty():
			won_key = ""
		return
	var names: Array[String] = []
	for winner: Dictionary in winners:
		names.append("%s (%s)" % [winner.city, winner.name])
	result_label.text = tr("Victory: %s. Leave or let the host continue without scoring.") % ", ".join(names)
	continue_button.disabled = not windows.coop.session.hosting
	rematch_button.disabled = not windows.coop.session.hosting
	end_scores.update(windows.players, true, windows.coop.session.token.sha256_text(), state.get("history", {}), str(goal.get("kind", "population")))
	var key := JSON.stringify(winners)
	if key != won_key:
		won_key = key
		firework_point = Vector2i(int(winners[0].point[0]), int(winners[0].point[1]))
		firework_started = Time.get_ticks_msec()
		last_burst = -1
		if state.get("mode") == "region" and state.get("view_owner") != winners[0].seat:
			windows.coop.session.request.call_deferred({"kind": "view_city", "seat": winners[0].seat})
		windows.coop.app.camera_input.center_map_on_tile.call_deferred(firework_point)
		windows.open_chat()
		windows.append_status(result_label.text)
		windows.coop.app.effects_audio.play_sound_ids([ToolSoundRules.SOUND_REWARD])
		if windows.coop.app.document_state.city.music_enabled():
			var audio := windows.coop.app.effects_audio.audio_controller
			previous_music = audio.current_track_id
			audio.play_music_track(MusicDirector.MAIN_THEME_TRACK, false, true)
		show_result.call_deferred()

func show_result() -> void:
	ending.popup_centered()
	ending.set_meta("center_after_fit", true)
	windows.fit_content(ending, end_rows, 1000)
	windows.dock_chat(false)

func draw_fireworks() -> void:
	if firework_started == 0 or not ending.visible:
		return
	var age := (Time.get_ticks_msec() - firework_started) / 1000.0
	if age > 12.0:
		return
	var map := windows.coop.app.map_view
	var point := MultiplayerMapOverlay.project(map.city, Vector2(firework_point)) * map.camera._view_scale() + map.camera._draw_offset(map.camera._view_scale())
	var burst_index := int(age / 0.65)
	if burst_index != last_burst:
		last_burst = burst_index
		if map.city.sound_enabled():
			fireworks_audio.volume_db = linear_to_db(clampf(float(windows.coop.app.preferences.effects_volume), 0, 1)) - 5
			fireworks_audio.play()
	# Purely visual, deterministic particles: no simulation RNG or disaster edits.
	for burst in 7:
		var phase := fmod(age + burst * 0.53, 2.6)
		if phase > 1.8:
			continue
		var origin := point + Vector2((burst - 2) * 52, -90 - (burst % 2) * 45)
		# Keep the celebration above the centred results instead of hidden behind it.
		origin.y = maxf(map.camera_view_rect.position.y + 45, minf(origin.y, ending.position.y - 65 - (burst % 2) * 25))
		var light := Color.from_hsv(fmod(burst * 0.23, 1.0), 0.55, 1.0)
		for ring in range(6, 0, -1):
			windows.overlay.draw_circle(origin, ring * 13.0 * (0.6 + phase), Color(light, maxf(0, 1.0 - phase) * 0.035))
		for spark in 36:
			var angle := TAU * spark / 36.0 + burst * 0.2
			var direction := Vector2(cos(angle), sin(angle))
			var position := origin + direction * phase * 56 + Vector2(0, phase * phase * 20)
			var color := Color.from_hsv(fmod(burst * 0.23, 1.0), 0.7, 1.0, 1.0 - phase / 1.8)
			windows.overlay.draw_circle(position, 4.0, Color(color, color.a * 0.18))
			windows.overlay.draw_line(position - direction * 10, position, color, 2.0, true)
			windows.overlay.draw_circle(position, 1.3, Color(1, 1, 0.85, color.a))

func restore_music() -> void:
	fireworks_audio.stop()
	if previous_music >= 0 and windows.coop.app.document_state.city != null and windows.coop.app.document_state.city.music_enabled():
		windows.coop.app.effects_audio.audio_controller.play_music_track(previous_music, false, true)
	previous_music = -1

func close() -> void:
	restore_music()
	if windows.coop.app.regions.window != null:
		windows.coop.app.regions.window.hide()
		windows.coop.app.regions.confirmation.hide()
	ending.hide()
	won_key = ""
	firework_started = 0


static func firework_sound() -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(22050 * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 41091
	var smooth := 0.0
	for index in 22050:
		var time := float(index) / 22050.0
		smooth = lerpf(smooth, noise.randf_range(-1, 1), 0.3)
		var envelope := minf(time * 100, 1) * exp(-time * 7)
		var value := (smooth * 0.75 + sin(TAU * 70 * time) * 0.25) * envelope
		bytes.encode_s16(index * 2, int(clampf(value, -1, 1) * 18000))
	sound.data = bytes
	return sound
