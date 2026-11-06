extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(AudioServer.get_driver_name() == "Dummy")
	var quiet := _gain_for_amplitude(0.06)
	var loud := _gain_for_amplitude(0.35)
	assert(is_equal_approx(quiet * 0.06, loud * 0.35))
	assert(is_equal_approx(_gain_for_amplitude(0.0), 1.0))

	var audio := CityAudioController.new()
	root.add_child(audio)
	audio.setup("", 0.5, 0.5, false)
	var manual := MusicBoxPlayback.new()
	root.add_child(manual)
	manual.setup("", 0.5, 0.0, false)
	var bus := AudioServer.get_bus_index(CityAudioController.MUSIC_AMBIENCE_BUS)
	var music_bus := AudioServer.get_bus_index(CityAudioController.MUSIC_BUS)
	assert(AudioServer.get_bus_send(music_bus) == CityAudioController.MUSIC_AMBIENCE_BUS)
	assert(AudioServer.get_bus_effect(music_bus, 0) is AudioEffectHardLimiter)
	assert(audio.recording_player.bus == manual.recording_player.bus)
	assert(audio.music_player._audio_player.bus == audio.recording_player.bus)
	var sample := AudioStreamWAV.new()
	sample.mix_rate = 8000
	var bytes := PackedByteArray()
	bytes.resize(800)
	bytes.fill(1)
	sample.data = bytes
	var recording := RecordedSoundtrack.Result.new()
	recording.stream = sample
	recording.gain = quiet
	manual._set_recording(recording)
	manual.set_music_output_gain(0.5)
	assert(is_equal_approx(manual.recording_player.volume_linear, 0.25 * quiet))

	manual.set_volumes(1.0, 0.0)
	manual.set_music_output_gain(1.0)
	assert(is_equal_approx(manual.recording_player.volume_linear, quiet))
	manual.set_volumes(0.5, 0.0)
	manual.set_music_output_gain(0.5)

	var siren := DisasterStartConstants.SOUND_SIREN
	audio.wave_stream_cache[500] = sample
	audio.wave_stream_cache[siren] = sample
	audio.play_sound_ids([500], true, CityViewMode.Mode.CITY, 2)
	assert(audio._warning_duck == null)
	audio.play_sound_ids([siren], false, CityViewMode.Mode.CITY, 2)
	assert(audio._warning_duck == null)
	audio.wave_sound_gate.stop()
	audio.set_volumes(0.5, 0.0)
	audio.play_sound_ids([siren], true, CityViewMode.Mode.CITY, 2)
	assert(audio._warning_duck == null)
	audio.wave_sound_gate.stop()
	audio.set_volumes(0.5, 0.5)
	audio.play_sound_ids([siren], true, CityViewMode.Mode.CITY, 2)
	var duck := audio._warning_duck
	assert(duck != null)
	duck.pause()
	duck.custom_step(0.05)
	assert(AudioServer.get_bus_volume_db(bus) < 0.0)
	assert(AudioServer.get_bus_volume_db(bus) > CityAudioController.WARNING_DUCK_DB)
	duck.custom_step(0.25)
	assert(is_equal_approx(AudioServer.get_bus_volume_db(bus), CityAudioController.WARNING_DUCK_DB))
	assert(is_equal_approx(manual.recording_player.volume_linear, 0.25 * quiet))
	duck.custom_step(2.0)
	assert(is_zero_approx(AudioServer.get_bus_volume_db(bus)))
	audio.stop_sound_effects()
	audio.play_sound_events([SoundEvent.looped(siren, 3)], true, CityViewMode.Mode.CITY, 2)
	assert(audio._warning_duck != null and audio.sound_loop_player != null)
	audio.stop_sound_loop()
	assert(is_zero_approx(AudioServer.get_bus_volume_db(bus)))

	print("PASS: track gain, crossfade gain, music routing and audible siren attack/hold/release")
	quit()


func _gain_for_amplitude(amplitude: float) -> float:
	var reader := func(_position: float, frames: int) -> PackedVector2Array:
		var samples := PackedVector2Array()
		samples.resize(frames)
		samples.fill(Vector2.ONE * amplitude)
		return samples
	return MusicLoudness.estimate(3.0, 1000.0, reader)
