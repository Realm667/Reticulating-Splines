class_name MusicBoxPlayback
extends CityAudioController
## Independent user playlist. Never connected to simulation music activity.

signal song_finished(track_id: Variant)
signal custom_failed

var custom_track := ""
var pack_key: Variant = null


func track_key() -> Variant:
	return pack_key if pack_key != null else (custom_track if not custom_track.is_empty() else current_track_id)


func play_pack(key: Variant, entry: Dictionary) -> bool:
	# Manual selection never falls through to another pack or the reference OST.
	music_pack = entry.pack
	original_media_enabled = false
	soundtrack_folder = ""
	var started := play_music_track(entry.id, false, true)
	if started:
		pack_key = key
	return started


func play_custom(id: String, path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	stop_music()
	custom_track = id
	current_track_name = MusicTrackTitle.resolve(path)
	announce_music()
	recording_loader.queue(PackedStringArray([path]))
	return true


func _process(delta: float) -> void:
	if custom_track.is_empty():
		super(delta)
		return
	var result := recording_loader.take_completed()
	if result != null:
		if result.stream == null:
			_fail_custom()
			return
		current_track_name = MusicTrackTitle.resolve(result.path)
		announce_music()
		recording_player.stream = result.stream
		recording_player.play()
		_sync_music_pause()
	if recording_loader.start_pending() != OK:
		_fail_custom()


func _fail_custom() -> void:
	stop_music()
	custom_failed.emit()


func music_playback_is_active() -> bool:
	return recording_loader.is_pending() or super()


func stop_music(clear_gap := true) -> void:
	custom_track = ""
	pack_key = null
	super(clear_gap)


func _on_music_track_finished(track_id: int) -> void:
	if track_id == current_track_id:
		var finished: Variant = track_key()
		stop_music()
		song_finished.emit(finished)
