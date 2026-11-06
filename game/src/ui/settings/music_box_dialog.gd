class_name MusicBoxDialog
extends QolDialog
## A local favorites player. The original music controller retains its timing
## and reports to the simulation while its audible output is faded out.

@warning_ignore_start("integer_division")

const ORIGINAL_TRACK_TITLES = MusicTrackTitle.ORIGINAL

var app: CityApplication
var playback: MusicBoxPlayback
var outgoing: MusicBoxPlayback
var soundfont_selector: OptionButton
var soundfont_description: Label
var transition_selector: OptionButton
var crossfade_seconds := 0.0
var _transition_waiting := false
var _fade_held := false
var _previous_soundfont := ""
var _previous_custom_path := ""
var _applied_soundfont := ""
var config := ConfigFile.new()
var storage_path := ""
var library: ItemList
var favorites_list: ItemList
var collection: ItemList
var progress: ProgressBar
var elapsed: Label
var track_tabs: TabContainer
var music_library := MusicBoxLibrary.new()
var playback_mode: Button
var playback_order := MusicBoxOrder.new()
var custom_music := CustomMusicLibrary.new()
var favorites: Array = []
var favorite_index := -1
var now_playing: Label
var status: Label
var play_button: Button
var add_favorite: Button
var remove_favorite: Button
var move_favorite: Button
var player_settings: TabContainer
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
	crossfade_seconds = float(config.get_value("player", "crossfade_seconds", 0.0))
	if crossfade_seconds not in [0.0, 2.0, 4.0]:
		crossfade_seconds = 0.0
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
	add_favorite = button(edit, "Add to favorites", _add_selected)
	remove_favorite = button(edit, "Remove", _remove_selected)
	move_favorite = button(edit, "Move up", _move_up)
	track_tabs.tab_changed.connect(func(_index: int) -> void: _sync_favorite_actions())
	library.item_selected.connect(func(_index: int) -> void: _sync_favorite_actions())
	favorites_list.item_selected.connect(func(_index: int) -> void: _sync_favorite_actions())
	var controls := row()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	button(controls, "Previous", func() -> void: step(-1))
	play_button = button(controls, "Play / Pause", _toggle_pause)
	play_button.theme_type_variation = "PrimaryButton"
	button(controls, "Next", func() -> void: step(1))
	progress = ProgressBar.new()
	progress.show_percentage = false
	column.add_child(progress)
	elapsed = label("", "HelpLabel")
	elapsed.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	player_settings = TabContainer.new()
	player_settings.custom_minimum_size.y = 190
	column.add_child(player_settings)
	var playback_settings := _settings_page("Playback")
	var playback_row := HBoxContainer.new()
	playback_settings.add_child(playback_row)
	var order_label := Label.new()
	order_label.text = "Playback order"
	playback_row.add_child(order_label)
	playback_mode = Button.new()
	playback_mode.toggle_mode = true
	playback_mode.toggled.connect(_set_shuffle_music)
	playback_row.add_child(playback_mode)
	_refresh_playback_mode()
	var sound_settings := _settings_page("Sound")
	var levels := GridContainer.new()
	levels.columns = 2
	levels.add_theme_constant_override("h_separation", 14)
	sound_settings.add_child(levels)
	var music_label := Label.new()
	music_label.text = "Music volume"
	levels.add_child(music_label)
	volume = HSlider.new()
	volume.custom_minimum_size.x = 140
	volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume.max_value = 100.0
	volume.value = clampf(float(config.get_value("player", "gain", 1.0)), 0.0, 1.0) * 100.0
	volume.value_changed.connect(_volume_changed)
	levels.add_child(volume)
	var effects_label := Label.new()
	effects_label.text = "Sound effects volume"
	levels.add_child(effects_label)
	var effects := HSlider.new()
	effects.custom_minimum_size.x = 140
	effects.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effects.max_value = 100.0
	effects.value = app.preferences.effects_volume * 100.0
	effects.value_changed.connect(func(value: float) -> void:
		app.preferences.effects_volume = value / 100.0
		app.audio_controller.set_volumes(app.preferences.music_volume, app.preferences.effects_volume)
		_effects_dirty = true
		_effects_save_delay = 0.5)
	levels.add_child(effects)
	var soundfonts := HBoxContainer.new()
	sound_settings.add_child(soundfonts)
	var soundfont_label := Label.new()
	soundfont_label.text = "Music SoundFont"
	soundfonts.add_child(soundfont_label)
	soundfont_selector = OptionButton.new()
	soundfont_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for choice in SoundFontCatalog.choices():
		soundfont_selector.add_item(SoundFontCatalog.label(choice))
		soundfont_selector.set_item_metadata(soundfont_selector.item_count - 1, choice)
		soundfont_selector.set_item_tooltip(soundfont_selector.item_count - 1, SoundFontCatalog.description(choice))
	soundfont_selector.item_selected.connect(func(index: int) -> void: _select_soundfont(str(soundfont_selector.get_item_metadata(index))))
	soundfonts.add_child(soundfont_selector)
	var picker := FileDialog.new()
	picker.title = "Select a SoundFont"
	picker.theme = AppUiTheme.file_dialog()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.sf2, *.sf3, *.dls ; General MIDI SoundFont"])
	picker.access = FileDialog.ACCESS_FILESYSTEM
	add_child(picker)
	picker.file_selected.connect(func(path: String) -> void: _select_soundfont(SoundFontCatalog.CUSTOM, path))
	button(soundfonts, "Browse...", func() -> void: picker.popup_centered_ratio(0.8))
	var compare := button(soundfonts, "A/B", _compare_soundfont)
	compare.tooltip_text = "Compare the current MIDI with the previous SoundFont at the same playback position."
	soundfont_description = Label.new()
	soundfont_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	soundfont_description.theme_type_variation = "HelpLabel"
	sound_settings.add_child(soundfont_description)
	var transitions := HBoxContainer.new()
	playback_settings.add_child(transitions)
	var transition_label := Label.new()
	transition_label.text = "Track transitions"
	transitions.add_child(transition_label)
	transition_selector = OptionButton.new()
	for seconds in [0, 2, 4]:
		transition_selector.add_item("Direct" if seconds == 0 else "%d s" % seconds)
		transition_selector.set_item_metadata(transition_selector.item_count - 1, seconds)
	transition_selector.select([0.0, 2.0, 4.0].find(crossfade_seconds))
	transition_selector.item_selected.connect(func(index: int) -> void:
		crossfade_seconds = float(transition_selector.get_item_metadata(index))
		_save())
	transitions.add_child(transition_selector)
	var automatic_row := HBoxContainer.new()
	playback_settings.add_child(automatic_row)
	var automatic_button := button(automatic_row, "Automatic music", automatic)
	automatic_button.tooltip_text = "Stop manual playback and let the game choose the music again."
	var library_settings := _settings_page("Library")
	var folders := HBoxContainer.new()
	library_settings.add_child(folders)
	button(folders, "Open music folder", _open_music_folder)
	button(folders, "Rescan", rescan)
	status = label("", "HelpLabel")
	_sync_favorite_actions()
	close_requested.connect(_save)


func _settings_page(title_text: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title_text
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	player_settings.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	return page


func _sync_favorite_actions() -> void:
	var editing_favorites := track_tabs.current_tab == 1
	add_favorite.visible = not editing_favorites
	remove_favorite.visible = editing_favorites
	move_favorite.visible = editing_favorites
	add_favorite.disabled = library.get_selected_items().is_empty()
	var selected := favorites_list.get_selected_items()
	remove_favorite.disabled = selected.is_empty()
	move_favorite.disabled = selected.is_empty() or selected[0] == 0


func _ready() -> void:
	playback = _new_playback()
	outgoing = _new_playback()
	app.audio_controller.set_music_output_gain(volume.value / 100.0)
	_refresh_soundfont()
	rescan()
	_refresh_favorites()


func _new_playback() -> MusicBoxPlayback:
	var player := MusicBoxPlayback.new()
	add_child(player)
	player.setup(app.audio_controller.reference_root, app.preferences.music_volume, 0.0, app.audio_controller.original_media_enabled)
	player.song_finished.connect(func(id: Variant) -> void:
		if active and player == playback:
			step(1, id))
	player.custom_failed.connect(func() -> void:
		if active and player == playback:
			_custom_failed())
	player.music_notice.connect(func(message: String) -> void:
		if active and player == playback and app.city_status_bar != null:
			app.city_status_bar.show_music_notice(message))
	player.music_activity_changed.connect(func(playing: bool) -> void:
		if not playing and player == playback and player.current_track_id >= 0:
			_recover_failed_playback.call_deferred())
	return player


func _refresh_soundfont() -> void:
	var choice := app.preferences.music_soundfont
	for index in soundfont_selector.item_count:
		var item_choice := str(soundfont_selector.get_item_metadata(index))
		soundfont_selector.set_item_tooltip(index, SoundFontCatalog.description(item_choice))
		if item_choice == choice:
			soundfont_selector.select(index)
	soundfont_description.text = SoundFontCatalog.description(choice) + " " + tr("SoundFonts affect MIDI only; recorded music keeps its original sound.")
	soundfont_selector.tooltip_text = soundfont_description.text


func _select_soundfont(choice: String, custom_path := "") -> void:
	var options := AppSettingsStore.SaveOptions.new()
	options.music_soundfont = choice
	options.music_soundfont_path = app.preferences.music_soundfont_path if custom_path.is_empty() else custom_path
	var error := AppSettingsStore.save_values(app.preferences.music_volume, app.preferences.effects_volume,
		app.preferences.fullscreen, app.preferences.settings_path, options)
	if error != OK:
		_refresh_soundfont()
		status.text = tr("Cannot save music preferences: %s") % error_string(error)
		return
	_previous_soundfont = app.preferences.music_soundfont
	_previous_custom_path = app.preferences.music_soundfont_path
	app.preferences.music_soundfont = choice
	app.preferences.music_soundfont_path = str(options.music_soundfont_path)
	_apply_soundfont()
	_refresh_soundfont()
	app.main_overlays.settings_dialog.show_soundfont(choice, app.preferences.music_soundfont_path, app.audio_controller.music_player.synth_status)


func _apply_soundfont() -> void:
	var key := app.preferences.music_soundfont + "|" + app.preferences.music_soundfont_path
	if key == _applied_soundfont:
		return
	_applied_soundfont = key
	for player in [app.audio_controller, playback, outgoing]:
		player.set_music_soundfont(app.preferences.music_soundfont, app.preferences.music_soundfont_path)


func _compare_soundfont() -> void:
	if _previous_soundfont.is_empty():
		_select_soundfont(SoundFontCatalog.FLUID if app.preferences.music_soundfont != SoundFontCatalog.FLUID else SoundFontCatalog.SYSTEM)
	else:
		_select_soundfont(_previous_soundfont, _previous_custom_path)


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
	_sync_favorite_actions()


func open() -> void:
	_refresh_soundfont()
	_refresh_playback_mode()
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
	if _fade != null:
		_fade.kill()
		_fade_held = false
	# Two independent players allow a real overlap, including MIDI synth tails.
	outgoing.stop_music()
	var previous := playback
	playback = outgoing
	outgoing = previous
	if crossfade_seconds == 0.0:
		outgoing.stop_music()
	_sync_source()
	active = true
	app.audio_controller.music_notices_enabled = false
	_playing_favorites = from_favorites
	playback.music_paused = false
	playback.set_music_output_gain(0.0 if crossfade_seconds > 0.0 else 1.0)
	var started := playback.play_pack(id, music_library.tracks[id]) if music_library.tracks.has(id) else playback.play_custom(id, custom_music.resolve(id))
	if not started:
		_custom_failed()
		return
	favorite_index = favorites.find(id)
	_refresh_favorites()
	_transition_waiting = true
	if playback.ready_to_fade():
		_begin_crossfade()


func _begin_crossfade() -> void:
	_transition_waiting = false
	if crossfade_seconds <= 0.0:
		app.audio_controller.set_music_output_gain(0.0)
		outgoing.stop_music()
		playback.set_music_output_gain(1.0)
		return
	_fade = create_tween().set_parallel(true)
	_fade.tween_method(app.audio_controller.set_music_output_gain, app.audio_controller.music_output_gain, 0.0, crossfade_seconds)
	_fade.tween_method(outgoing.set_music_output_gain, outgoing.music_output_gain, 0.0, crossfade_seconds)
	_fade.tween_method(playback.set_music_output_gain, 0.0, 1.0, crossfade_seconds)
	var fading := outgoing
	_fade.finished.connect(func() -> void: fading.stop_music())


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
	if app.preferences.shuffle_music:
		var available := ids.filter(_available)
		var next: Variant = playback_order.next_track(available, finished_track if finished_track != null else playback.track_key(), direction)
		if next != null:
			play_track(next, use_favorites)
		else:
			automatic()
			status.text = tr("This music track is not available.")
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


func automatic(immediate := false) -> void:
	status.text = ""
	_switch_serial += 1
	_transition_waiting = false
	if _fade != null:
		_fade.kill()
		_fade_held = false
	active = false
	app.audio_controller.music_notices_enabled = true
	outgoing.stop_music()
	var duration := 0.0 if immediate else crossfade_seconds
	if duration <= 0.0:
		playback.stop_music()
		app.audio_controller.set_music_output_gain(volume.value / 100.0)
	else:
		_fade = create_tween().set_parallel(true)
		_fade.tween_method(playback.set_music_output_gain, playback.music_output_gain, 0.0, duration)
		_fade.tween_method(app.audio_controller.set_music_output_gain, app.audio_controller.music_output_gain, volume.value / 100.0, duration)
		_fade.finished.connect(playback.stop_music)
	if app.audio_controller.music_playback_is_active():
		app.audio_controller.announce_music()


func _volume_changed(_value: float) -> void:
	if playback != null:
		_sync_source()
		if not active:
			if _fade != null:
				_fade.kill()
				_fade_held = false
			playback.stop_music()
			outgoing.stop_music()
			_transition_waiting = false
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
			automatic(true)
		else:
			var target_volume := app.audio_controller.music_volume * volume.value / 100.0
			if not is_equal_approx(playback.music_volume, target_volume):
				playback.set_volumes(target_volume, 0.0)
			playback.application_has_focus = app.audio_controller.application_has_focus
			playback.background_audio = app.audio_controller.background_audio
			playback.focus_paused = app.audio_controller.focus_paused
			playback._sync_music_pause()
	_apply_soundfont()
	if not active:
		for player in [playback, outgoing]:
			player.application_has_focus = app.audio_controller.application_has_focus
			player.background_audio = app.audio_controller.background_audio
			player.focus_paused = app.audio_controller.focus_paused
			player.music_paused = app.audio_controller.music_paused
			player._sync_music_pause()
	if active:
		outgoing.set_volumes(playback.music_volume, 0.0)
		outgoing.music_paused = playback.music_paused
		outgoing.application_has_focus = playback.application_has_focus
		outgoing.background_audio = playback.background_audio
		outgoing.focus_paused = playback.focus_paused
		outgoing._sync_music_pause()
		var paused := playback.music_paused or playback.focus_paused or not playback.audio_allowed()
		if _fade != null and _fade.is_valid():
			if paused and _fade.is_running():
				_fade.pause()
				_fade_held = true
			elif not paused and _fade_held:
				_fade.play()
				_fade_held = false
		if _transition_waiting and playback.ready_to_fade():
			_begin_crossfade()
		if crossfade_seconds > 0.0 and not paused and not _transition_waiting and (_fade == null or not _fade.is_running()):
			var remaining := playback.remaining_seconds()
			if remaining > 0.0 and remaining <= crossfade_seconds and outgoing.recording_player.stream == null:
				step(1)
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


func _refresh_playback_mode() -> void:
	playback_mode.set_pressed_no_signal(app.preferences.shuffle_music)
	playback_mode.text = "Shuffle" if app.preferences.shuffle_music else "In order"
	playback_mode.tooltip_text = "Switch between sequential and shuffled playback for the selected collection or favorites."


func _set_shuffle_music(enabled: bool) -> void:
	var options := AppSettingsStore.SaveOptions.new()
	options.shuffle_music = enabled
	var error := AppSettingsStore.save_values(app.preferences.music_volume, app.preferences.effects_volume,
		app.preferences.fullscreen, app.preferences.settings_path, options)
	if error != OK:
		_refresh_playback_mode()
		status.text = tr("Cannot save music preferences: %s") % error_string(error)
		return
	app.preferences.shuffle_music = enabled
	app.audio_controller.set_shuffle_music(enabled)
	playback_order.reset()
	_refresh_playback_mode()


func _save() -> void:
	config.set_value("player", "favorites", favorites.duplicate())
	config.set_value("player", "favorites_version", 1)
	config.set_value("player", "gain", volume.value / 100.0)
	config.set_value("player", "crossfade_seconds", crossfade_seconds)
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
	for index in ["Playback", "Sound", "Library"].size():
		player_settings.set_tab_title(index, tr(["Playback", "Sound", "Library"][index]))
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
		_refresh_soundfont()
