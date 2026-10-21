class_name MusicBoxDialog
extends QolDialog
## A local favorites player. The original music controller retains its timing
## and reports to the simulation while its audible output is faded out.

@warning_ignore_start("integer_division")

const ORIGINAL_TRACK_TITLES = MusicTrackTitle.ORIGINAL

var app: CityApplication
var playback: MusicBoxPlayback
var config := ConfigFile.new()
var storage_path := ""
var library: ItemList
var favorites_list: ItemList
var collection: ItemList
var progress: ProgressBar
var elapsed: Label
var track_tabs: TabContainer
var music_library := MusicBoxLibrary.new()
var shuffle_music_check: CheckBox
var custom_music := CustomMusicLibrary.new()
var favorites: Array = []
var favorite_index := -1
var now_playing: Label
var status: Label
var play_button: Button
var volume: HSlider
var active := false
var _playing_favorites := false
var _fade: Tween
var _switch_serial := 0
var _refresh_elapsed := 0.0
var _effects_dirty := false
var _effects_save_delay := 0.0
var _highlighted_key: Variant = null


func _init(application: CityApplication) -> void:
	super()
	app = application
	title = "Music box"
	min_size = Vector2i(590, 470)
	storage_path = app.preferences.settings_path + ".music-box.cfg"
	config.load(storage_path)
	favorites = _saved_favorites(config)
	now_playing = label("", "SectionHeading")
	now_playing.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	now_playing.autowrap_mode = TextServer.AUTOWRAP_OFF
	now_playing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	now_playing.clip_text = true
	var lists := row()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	collection = ItemList.new()
	collection.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	collection.custom_minimum_size = Vector2(170, 210)
	collection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection.size_flags_stretch_ratio = 0.38
	collection.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	collection.item_selected.connect(func(_index: int) -> void: _refresh_library())
	lists.add_child(collection)
	track_tabs = TabContainer.new()
	track_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_tabs.custom_minimum_size.x = 270
	lists.add_child(track_tabs)
	library = ItemList.new()
	library.name = "Tracks"
	library.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	library.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	library.item_activated.connect(func(index: int) -> void: play_track(library.get_item_metadata(index)))
	track_tabs.add_child(library)
	favorites_list = ItemList.new()
	favorites_list.name = "Favorites"
	favorites_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	favorites_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	favorites_list.item_activated.connect(func(index: int) -> void:
		favorite_index = index
		play_track(favorites[index], true))
	track_tabs.add_child(favorites_list)
	var edit := row()
	button(edit, "Add to favorites", _add_selected)
	button(edit, "Remove", _remove_selected)
	button(edit, "Move up", _move_up)
	var controls := row()
	var transport_panel := VBoxContainer.new()
	transport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(transport_panel)
	var transport := HBoxContainer.new()
	transport_panel.add_child(transport)
	button(transport, "Previous", func() -> void: step(-1))
	play_button = button(transport, "Play / Pause", _toggle_pause)
	play_button.theme_type_variation = "PrimaryButton"
	button(transport, "Next", func() -> void: step(1))
	progress = ProgressBar.new()
	progress.show_percentage = false
	transport_panel.add_child(progress)
	elapsed = Label.new()
	elapsed.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	transport_panel.add_child(elapsed)
	var levels := VBoxContainer.new()
	levels.custom_minimum_size.x = 180
	levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(levels)
	var music_label := Label.new()
	music_label.text = "Music volume"
	levels.add_child(music_label)
	volume = HSlider.new()
	volume.max_value = 100.0
	volume.value = clampf(float(config.get_value("player", "gain", 1.0)), 0.0, 1.0) * 100.0
	volume.value_changed.connect(_volume_changed)
	levels.add_child(volume)
	var effects_label := Label.new()
	effects_label.text = "Sound effects volume"
	levels.add_child(effects_label)
	var effects := HSlider.new()
	effects.max_value = 100.0
	effects.value = app.preferences.effects_volume * 100.0
	effects.value_changed.connect(func(value: float) -> void:
		app.preferences.effects_volume = value / 100.0
		app.audio_controller.set_volumes(app.preferences.music_volume, app.preferences.effects_volume)
		_effects_dirty = true
		_effects_save_delay = 0.5)
	levels.add_child(effects)
	button(row(), "Automatic music", automatic)
	shuffle_music_check = CheckBox.new()
	shuffle_music_check.text = "Shuffle all music"
	shuffle_music_check.tooltip_text = "Play all 19 tracks, including menu and special music, once per shuffle cycle."
	shuffle_music_check.set_pressed_no_signal(app.preferences.shuffle_music)
	shuffle_music_check.toggled.connect(_set_shuffle_music)
	column.add_child(shuffle_music_check)
	var folders := row()
	button(folders, "Open music folder", _open_music_folder)
	button(folders, "Rescan", rescan)
	status = label("", "HelpLabel")
	close_requested.connect(_save)


func _ready() -> void:
	playback = MusicBoxPlayback.new()
	add_child(playback)
	playback.setup(app.audio_controller.reference_root, app.preferences.music_volume, 0.0, app.audio_controller.original_media_enabled)
	app.audio_controller.set_music_output_gain(volume.value / 100.0)
	playback.song_finished.connect(func(id: Variant) -> void: step(1, id))
	playback.custom_failed.connect(_custom_failed)
	playback.music_notice.connect(func(message: String) -> void:
		if active and app.city_status_bar != null:
			app.city_status_bar.show_music_notice(message))
	playback.music_activity_changed.connect(func(playing: bool) -> void:
		if not playing and playback.current_track_id >= 0:
			_recover_failed_playback.call_deferred())
	rescan()
	_refresh_favorites()


static func _saved_favorites(saved: ConfigFile) -> Array:
	var result := _track_ids(saved.get_value("player", "favorites", []))
	if int(saved.get_value("player", "favorites_version", 0)) < 1:
		for id: Variant in _track_ids(saved.get_value("player", "queue", [])):
			if id not in result:
				result.append(id)
	return result


static func _track_ids(value: Variant) -> Array:
	var result: Array = []
	if value is Array or value is PackedInt32Array:
		for id: Variant in value:
			if id is int and id >= MusicDirector.FIRST_TRACK_ID and id < MusicDirector.FIRST_TRACK_ID + MusicDirector.TRACK_COUNT and id not in result:
				result.append(id)
			elif id is String and (CustomMusicLibrary.valid_id(id) or MusicBoxLibrary.valid_key(id)) and id not in result:
				result.append(id)
	return result


func _source_name(source: String) -> String:
	if source == "original":
		return tr("SC2000 original music")
	if source == "reticulating":
		return "Reticulating Splines"
	return music_library.sources.get(source, tr("My music"))


func track_name(id: Variant) -> String:
	if music_library.tracks.has(id):
		var entry: Dictionary = music_library.tracks[id]
		var name: String = ORIGINAL_TRACK_TITLES.get(entry.id, entry.title) if entry.source == "original" else entry.title
		return _source_name(entry.source) + " — " + name
	if id is int:
		return tr("SC2000 original music") + " — " + ORIGINAL_TRACK_TITLES.get(id, tr("Track %d") % id)
	if MusicBoxLibrary.valid_key(str(id)):
		return _source_name(str(id).get_slice(":", 0)) + " — " + tr("Track %d") % int(str(id).get_slice(":", 1))
	return tr("My music") + " — " + Mp3Title.read(custom_music.resolve(str(id))) if not custom_music.resolve(str(id)).is_empty() else tr("My music") + " — " + str(id).get_basename()


func song_title(id: Variant) -> String:
	if music_library.tracks.has(id):
		var entry: Dictionary = music_library.tracks[id]
		return ORIGINAL_TRACK_TITLES.get(entry.id, entry.title) if entry.source == "original" else entry.title
	if id is String and CustomMusicLibrary.valid_id(id):
		var path := custom_music.resolve(id)
		return Mp3Title.read(path) if not path.is_empty() else id.get_file().get_basename()
	return track_name(id)


func _list_title(id: Variant) -> String:
	var selected := collection.get_selected_items()
	var name := track_name(id) if selected.is_empty() or collection.get_item_metadata(selected[0]) == "all" else song_title(id)
	return ("★ " if id in favorites else "") + name


func _available(id: Variant) -> bool:
	if music_library.tracks.has(id):
		return music_library.available(id)
	return id is String and CustomMusicLibrary.valid_id(id) and not custom_music.resolve(id).is_empty()


func _manual_track_name() -> String:
	var key: Variant = playback.track_key()
	var source := _source_name(music_library.tracks[key].source) if music_library.tracks.has(key) else tr("My music")
	return source + " — " + playback.current_track_name


func _automatic_track_name(player: CityAudioController) -> String:
	var id := player.current_track_id
	if id < MusicDirector.FIRST_TRACK_ID:
		return tr("No track playing")
	# The automatic controller may use a different pack from the manual player.
	var pack := player.music_pack
	var path := str(pack.files.get(id, ""))
	if not path.is_empty():
		var source := MusicBoxLibrary.source_for(pack)
		var source_name := _source_name(source) if source != "pack" else pack.pack_name
		var name := player.current_track_name
		return source_name + " — " + name
	var recordings := RecordedSoundtrack.find_tracks(player.soundtrack_folder, id)
	if not recordings.is_empty():
		return tr("My music") + " — " + player.current_track_name
	return tr("SC2000 original music") + " — " + ORIGINAL_TRACK_TITLES.get(id, player.current_track_name) if player.original_media_enabled else tr("No track playing")


func _refresh_library() -> void:
	_highlighted_key = null
	var selected: Variant = library.get_item_metadata(library.get_selected_items()[0]) if not library.get_selected_items().is_empty() else null
	library.clear()
	var source := str(collection.get_item_metadata(collection.get_selected_items()[0])) if not collection.get_selected_items().is_empty() else "all"
	var ids: Array = []
	for key in music_library.tracks:
		if source == "all" or source == music_library.tracks[key].source:
			ids.append(key)
	for id in custom_music.tracks:
		if source in ["all", "custom"] or source == "folder:" + id.get_base_dir():
			ids.append(id)
	for id: Variant in ids:
		var index := library.add_item(_list_title(id))
		library.set_item_metadata(index, id)
		var path: String = music_library.tracks[id].path if music_library.tracks.has(id) else custom_music.resolve(id)
		library.set_item_tooltip(index, track_name(id) + "\n" + path)
		if typeof(id) == typeof(selected) and id == selected:
			library.select(index)


func _refresh_favorites() -> void:
	favorites_list.clear()
	for id in favorites:
		favorites_list.add_item(track_name(id) + ("" if _available(id) else " — " + tr("This music track is not available.")))
	if favorite_index >= 0 and favorite_index < favorites.size():
		favorites_list.select(favorite_index)


func open() -> void:
	shuffle_music_check.set_pressed_no_signal(app.preferences.shuffle_music)
	rescan()
	_refresh_favorites()
	popup_centered(Vector2i(760, 620))


func _add_selected() -> void:
	for index in library.get_selected_items():
		var id: Variant = library.get_item_metadata(index)
		if id not in favorites:
			favorites.append(id)
	_refresh_favorites()
	_refresh_library()
	_save()


func _remove_selected() -> void:
	var selected := favorites_list.get_selected_items()
	if selected.is_empty():
		return
	var removed: Variant = favorites[selected[0]]
	favorites.remove_at(selected[0])
	favorite_index = selected[0] - 1 if removed == playback.track_key() else favorites.find(playback.track_key())
	_refresh_library()
	if favorites.is_empty() and active and _playing_favorites:
		automatic()
	_refresh_favorites()
	_save()


func _move_up() -> void:
	var selected := favorites_list.get_selected_items()
	if selected.is_empty() or selected[0] == 0:
		return
	var index := selected[0]
	var id: Variant = favorites[index]
	favorites[index] = favorites[index - 1]
	favorites[index - 1] = id
	favorite_index = favorites.find(playback.track_key())
	_refresh_favorites()
	favorites_list.select(index - 1)
	_save()


func _sync_source() -> void:
	var original := app.audio_controller
	playback.set_music_soundfont(app.preferences.music_soundfont, app.preferences.music_soundfont_path)
	playback.set_background_audio(original.background_audio)
	playback.application_has_focus = original.application_has_focus
	playback.set_volumes(original.music_volume * volume.value / 100.0, 0.0)


func play_track(id: Variant, from_favorites := false) -> void:
	status.text = ""
	if not _available(id):
		automatic()
		status.text = tr("This music track is not available.")
		return
	if app.document_state.city != null and not app.document_state.city.music_enabled():
		status.text = tr("Enable Music in Options to play a track.")
		return
	_switch_serial += 1
	var serial := _switch_serial
	if _fade != null:
		_fade.kill()
	_sync_source()
	active = true
	app.audio_controller.music_notices_enabled = false
	_playing_favorites = from_favorites
	playback.music_paused = false
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_method(app.audio_controller.set_music_output_gain, app.audio_controller.music_output_gain, 0.0, 0.15)
	_fade.tween_method(playback.set_music_output_gain, playback.music_output_gain, 0.0, 0.15)
	await _fade.finished
	if serial != _switch_serial:
		return
	if not _available(id):
		automatic()
		status.text = tr("This music track is not available.")
		return
	var started := playback.play_pack(id, music_library.tracks[id]) if music_library.tracks.has(id) else playback.play_custom(id, custom_music.resolve(id))
	if not started:
		if id is String and CustomMusicLibrary.valid_id(id):
			_custom_failed()
		else:
			automatic()
			status.text = tr("This music track is not available.")
		return
	favorite_index = favorites.find(id)
	_refresh_favorites()
	_fade = create_tween()
	_fade.tween_method(playback.set_music_output_gain, 0.0, 1.0, 0.2)


func step(direction: int, finished_track: Variant = null) -> void:
	var use_favorites := _playing_favorites if active else track_tabs.current_tab == 1
	var ids := favorites.duplicate() if use_favorites else []
	if not use_favorites:
		for index in library.item_count:
			ids.append(library.get_item_metadata(index))
	if ids.is_empty():
		if finished_track != null or use_favorites:
			automatic()
		if use_favorites:
			status.text = tr("Add tracks to your favorites to play them.")
		return
	var index := ids.find(finished_track if finished_track != null else playback.track_key())
	if index < 0:
		index = favorite_index if use_favorites and active else (-1 if direction > 0 else 0)
	# Unavailable favorites remain saved, but are skipped without playing other music.
	for offset in range(1, ids.size() + 1):
		var next: Variant = ids[posmod(index + direction * offset, ids.size())]
		if _available(next):
			play_track(next, use_favorites)
			return
	automatic()
	status.text = tr("This music track is not available.")


func _toggle_pause() -> void:
	if not active or (track_tabs.current_tab == 1 and not _playing_favorites):
		var use_favorites := track_tabs.current_tab == 1
		var list := favorites_list if use_favorites else library
		var selected := list.get_selected_items()
		if not selected.is_empty():
			var id: Variant = favorites[selected[0]] if use_favorites else library.get_item_metadata(selected[0])
			play_track(id, use_favorites)
		else:
			if use_favorites:
				_playing_favorites = true
			step(1)
	else:
		playback._set_music_paused(not playback.music_paused)


func automatic() -> void:
	status.text = ""
	_switch_serial += 1
	if _fade != null:
		_fade.kill()
	active = false
	app.audio_controller.music_notices_enabled = true
	playback.stop_music()
	if app.audio_controller.music_playback_is_active():
		app.audio_controller.announce_music()
	_fade = create_tween()
	_fade.tween_method(app.audio_controller.set_music_output_gain, app.audio_controller.music_output_gain, volume.value / 100.0, 0.2)


func _volume_changed(_value: float) -> void:
	if playback != null:
		_sync_source()
		if not active:
			if _fade != null:
				_fade.kill()
			app.audio_controller.set_music_output_gain(volume.value / 100.0)
	_save()


func _recover_failed_playback() -> void:
	if active and not playback.music_paused and not playback.music_playback_is_active():
		automatic()
		status.text = tr("This music track is not available.")


func _process(delta: float) -> void:
	if playback == null:
		return
	if _effects_dirty:
		_effects_save_delay -= delta
		if _effects_save_delay <= 0.0:
			_save_effects()
	if active:
		if app.document_state.city != null and not app.document_state.city.music_enabled():
			automatic()
		else:
			var target_volume := app.audio_controller.music_volume * volume.value / 100.0
			if not is_equal_approx(playback.music_volume, target_volume):
				playback.set_volumes(target_volume, 0.0)
			playback.application_has_focus = app.audio_controller.application_has_focus
			playback.background_audio = app.audio_controller.background_audio
			playback.focus_paused = app.audio_controller.focus_paused
			playback._sync_music_pause()
	_refresh_elapsed += delta
	if not visible or _refresh_elapsed < 0.25:
		return
	_refresh_elapsed = 0.0
	var player: CityAudioController = playback if active else app.audio_controller
	var track := _manual_track_name() if active else _automatic_track_name(player)
	var current: Variant = playback.track_key() if active else MusicBoxLibrary.key_for(player.music_pack, player.current_track_id)
	if typeof(current) != typeof(_highlighted_key) or current != _highlighted_key:
		_highlighted_key = current
		for index in library.item_count:
			var id: Variant = library.get_item_metadata(index)
			library.set_item_text(index, ("▶ " if typeof(id) == typeof(current) and id == current else "") + _list_title(id))
	var stream := player.recording_player.stream
	var duration := stream.get_length() if stream != null else 0.0
	var position := player.recording_player.get_playback_position() if stream != null else 0.0
	progress.max_value = maxf(duration, 1.0)
	progress.value = position
	elapsed.text = "%d:%02d / %d:%02d" % [int(position) / 60, int(position) % 60, int(duration) / 60, int(duration) % 60] if duration > 0.0 else "— / —"
	now_playing.text = tr("Paused: %s") % track if player.music_paused else tr("Playing: %s") % track
	if not active:
		now_playing.text = tr("Automatic music") + " — " + now_playing.text
	now_playing.tooltip_text = now_playing.text


func _set_shuffle_music(enabled: bool) -> void:
	var options := AppSettingsStore.SaveOptions.new()
	options.shuffle_music = enabled
	var error := AppSettingsStore.save_values(app.preferences.music_volume, app.preferences.effects_volume,
		app.preferences.fullscreen, app.preferences.settings_path, options)
	if error != OK:
		shuffle_music_check.set_pressed_no_signal(app.preferences.shuffle_music)
		status.text = tr("Cannot save music preferences: %s") % error_string(error)
		return
	app.preferences.shuffle_music = enabled
	app.audio_controller.set_shuffle_music(enabled)


func _save() -> void:
	config.set_value("player", "favorites", favorites.duplicate())
	config.set_value("player", "favorites_version", 1)
	config.set_value("player", "gain", volume.value / 100.0)
	var error := config.save(storage_path)
	if error != OK:
		status.text = tr("Cannot save music preferences: %s") % error_string(error)


func _exit_tree() -> void:
	_save_effects()
	if is_instance_valid(app.audio_controller):
		app.audio_controller.music_notices_enabled = true
		app.audio_controller.set_music_output_gain(1.0)


func _save_effects() -> void:
	if not _effects_dirty:
		return
	_effects_dirty = false
	var error := AppSettingsStore.save_values(app.preferences.music_volume, app.preferences.effects_volume,
		app.preferences.fullscreen, app.preferences.settings_path)
	if error != OK:
		status.text = tr("Cannot save music preferences: %s") % error_string(error)


func handle_media_key(key: int) -> bool:
	match key:
		KEY_MEDIAPLAY:
			_toggle_pause()
		KEY_MEDIANEXT:
			step(1)
		KEY_MEDIAPREVIOUS:
			step(-1)
		KEY_MEDIASTOP:
			playback._set_music_paused(true)
		_:
			return false
	return true


func rescan() -> void:
	var selected := str(collection.get_item_metadata(collection.get_selected_items()[0])) if not collection.get_selected_items().is_empty() else "all"
	custom_music.refresh()
	music_library.refresh(app.asset_state.data_pack, app.audio_controller.music_pack, PackLibrary.bundled_folder("music"))
	if active and playback.pack_key != null and not _available(playback.pack_key):
		automatic()
	collection.clear()
	var entries := [[tr("All music"), "all"]]
	for source in ["original", "reticulating", "pack"]:
		if music_library.sources.has(source):
			entries.append([_source_name(source), source])
	if custom_music.tracks.any(func(id: String) -> bool: return id.get_base_dir().is_empty()):
		entries.append([custom_music.folder_name(""), "folder:"])
	for entry in entries:
		collection.add_item(entry[0])
		collection.set_item_metadata(collection.item_count - 1, entry[1])
		collection.set_item_tooltip(collection.item_count - 1, entry[0])
	var folders := custom_music.folders
	for folder in folders:
		var name := custom_music.folder_name(folder)
		collection.add_item(name)
		collection.set_item_tooltip(collection.item_count - 1, name + "\n" + folder if name != folder else folder)
		collection.set_item_metadata(collection.item_count - 1, "folder:" + folder)
	for index in collection.item_count:
		if collection.get_item_metadata(index) == selected:
			collection.select(index)
	if collection.get_selected_items().is_empty() and collection.item_count > 0:
		collection.select(0)
	collection.tooltip_text = custom_music.folder
	track_tabs.set_tab_title(0, tr("Tracks"))
	track_tabs.set_tab_title(1, tr("Favorites"))
	_refresh_library()
	_refresh_favorites()
	status.text = tr("My music: %d MP3 files") % custom_music.tracks.size()


func _open_music_folder() -> void:
	var error := DirAccess.make_dir_recursive_absolute(custom_music.folder)
	if error == OK:
		error = OS.shell_open(ProjectSettings.globalize_path(custom_music.folder))
	if error != OK:
		status.text = tr("Cannot open music folder: %s") % error_string(error)


func _custom_failed() -> void:
	automatic()
	status.text = tr("This MP3 is missing or cannot be played. Automatic music resumed.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		rescan()
