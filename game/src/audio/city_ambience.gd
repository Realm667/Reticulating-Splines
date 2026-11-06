class_name CityAmbience
extends RefCounted
## Local mix of the current camera view. Reads completed presentation and map data.

const ASSETS := "res://assets/audio/ambience/"
const NEAR_BUS := &"City Ambience"
const FAR_BUS := &"City Ambience Distance"
const UPDATE_SECONDS := 0.24
const MAX_SHOTS := 4
const BEDS := ["street", "wet_street", "people", "shore", "river", "falls", "industry", "nature", "wind", "distant"]
const BASE_GAINS := [0.21, 0.19, 0.14, 0.24, 0.20, 0.29, 0.15, 0.095, 0.18, 0.14]

var app: CityApplication
var root: Node2D
var distant_filter: AudioEffectLowPassFilter
var beds: Dictionary[String, Voice] = {}
var shots: Array[Voice] = []
var streams: Dictionary[String, AudioStreamOggVorbis] = {}
var source_cooldown: Dictionary[String, float] = {}
var random := RandomNumberGenerator.new()
var city_id := 0
var elapsed := 0.0
var refresh_in := 0.0
var height := 0.0
var rain := 0.0
var night := 0.0
var next_wave := 4.0
var next_gull := 7.0
var next_cheer := 13.0


func _init(application: CityApplication) -> void:
	app = application


func process(delta: float, preparing: bool) -> void:
	var city := app.document_state.city
	var map := app.map_view
	var enabled := app.preferences.city_ambience_enabled and app.preferences.city_ambience_volume > 0.0
	if not enabled or city == null or not is_instance_valid(map) or map.city == null \
			or not city.sound_enabled() or app.audio_controller == null or not app.audio_controller.audio_allowed() \
			or (is_instance_valid(app.main_menu) and app.main_menu.visible) or app.view_state.overlay_mode != CityViewMode.Mode.CITY \
			or app.tool_state.landscape_editor:
		stop()
		return

	if city.document.get_instance_id() != city_id:
		stop()
		city_id = city.document.get_instance_id()

	if preparing:
		return
	if not is_instance_valid(root):
		_create_mixer()
	root.show()
	elapsed += delta
	refresh_in -= delta
	var zoom := map.zoom_factor
	var height_target := 1.0 - smoothstep(0.12, 0.54, zoom)
	var blend := 1.0 - exp(-4.0 * delta)
	height = lerpf(height, height_target, blend)
	distant_filter.cutoff_hz = lerpf(3900.0, 680.0, height)

	if refresh_in <= 0.0:
		refresh_in = UPDATE_SECONDS
		_sample(city, map, zoom)

	var view := _listening_area(map)
	var volume := app.preferences.city_ambience_volume
	for voice in beds.values():
		var pan_strength := (1.0 - height * 0.8) if voice.player.bus == NEAR_BUS else 0.18
		_mix(voice, delta, volume, pan_strength)
	for index in range(shots.size() - 1, -1, -1):
		var voice := shots[index]
		if not voice.player.playing:
			voice.player.queue_free()
			shots.remove_at(index)
			continue
		# Sources move with the actual local presentation while the clip plays.
		if voice.figure != null:
			voice.position = voice.figure.position
		elif voice.record >= 0:
			var track: CityTrafficMotion.Track = app.moving_sprites.traffic_motion.tracks.get(voice.record)
			if track != null:
				voice.position = _track_position(city, track)
		voice.target = voice.strength * _distance_gain(view, voice.position, voice.reach) \
			* (1.0 - height * 0.94)
		voice.target_pan = _pan(view, voice.position)
		_mix(voice, delta, volume, 1.0 - height)


func stop() -> void:
	if not is_instance_valid(root) or not root.visible:
		return
	root.hide()
	for voice in beds.values():
		voice.player.stop()
		voice.gain = 0.0
		voice.target = 0.0
		voice.pan = 0.0
	for voice in shots:
		voice.player.stop()
		voice.player.queue_free()
	shots.clear()
	source_cooldown.clear()
	elapsed = 0.0
	refresh_in = 0.0
	height = 0.0
	next_wave = 4.0
	next_gull = 7.0
	next_cheer = 13.0


func _create_mixer() -> void:
	root = Node2D.new()
	root.name = "CityAmbience"
	app.add_child(root)
	_bus(NEAR_BUS)
	var far_bus := _bus(FAR_BUS)
	if AudioServer.get_bus_effect_count(far_bus) == 0:
		distant_filter = AudioEffectLowPassFilter.new()
		distant_filter.cutoff_hz = 1800.0
		AudioServer.add_bus_effect(far_bus, distant_filter)
		var reflection := AudioEffectReverb.new()
		reflection.room_size = 0.28
		reflection.damping = 0.82
		reflection.dry = 0.93
		reflection.wet = 0.075
		AudioServer.add_bus_effect(far_bus, reflection)
	else:
		distant_filter = AudioServer.get_bus_effect(far_bus, 0) as AudioEffectLowPassFilter

	for index in BEDS.size():
		var kind: String = BEDS[index]
		var voice := _voice("street" if kind == "distant" else kind, true,
			FAR_BUS if kind == "distant" else NEAR_BUS)
		if voice != null:
			voice.strength = BASE_GAINS[index]
			beds[kind] = voice
	if beds.has("wind"):
		beds.wind.player.panning_strength = 0.0


static func _bus(bus_name: StringName) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, bus_name)
	return index


func _voice(kind: String, loop: bool, bus: StringName) -> Voice:
	if not streams.has(kind):
		var path := ASSETS + kind + ".ogg"
		if not ResourceLoader.exists(path, "AudioStreamOggVorbis"):
			return null
		streams[kind] = load(path) as AudioStreamOggVorbis
	var stream := streams[kind]
	if stream == null:
		return null
	var voice := Voice.new()
	voice.player = AudioStreamPlayer2D.new()
	voice.player.stream = stream.duplicate() as AudioStreamOggVorbis
	voice.player.stream.loop = loop
	voice.player.bus = bus
	# Distance in source coordinates is mixed here. Godot supplies stereo panning.
	voice.player.attenuation = 0.0
	voice.player.max_distance = 10000.0
	voice.player.panning_strength = 0.65
	voice.player.volume_linear = 0.0
	root.add_child(voice.player)
	return voice


func _mix(voice: Voice, delta: float, volume: float, pan_strength: float) -> void:
	var blend := 1.0 - exp(-4.0 * delta)
	voice.gain = lerpf(voice.gain, voice.target, blend)
	voice.pan = lerpf(voice.pan, voice.target_pan, blend)
	var viewport := app.get_viewport().get_visible_rect()
	voice.player.position = viewport.get_center() + Vector2(voice.pan * viewport.size.x * 0.44 * pan_strength, 0)
	voice.player.volume_linear = voice.gain * volume
	if voice.gain > 0.0015 and not voice.player.playing:
		voice.player.play(random.randf_range(0.0, voice.player.stream.get_length()))
	elif voice.gain <= 0.0015 and voice.target <= 0.0015 and voice.player.playing:
		voice.player.stop()


func _sample(city: CityState, map: CityMapControl, zoom: float) -> void:
	var view := _listening_area(map)
	var center := map.camera.center_tile().clamp(Vector2i.ZERO, Vector2i.ONE * (city.map_size - 1))
	var weather := app.visual_environment.weather
	var environment := app.visual_environment
	var options := app.preferences.visual_enhancements
	rain = clampf(weather.rain * environment.clouds.precipitation_readiness * 4.0, 0.0, 1.0)
	var hour := environment.phase * 24.0 if options.day_mode == 0 else float(options.day_hour)
	night = CityVisualEnvironment.light_at_hour(hour, options.night_strength).night if options.day_enabled else 0.0
	var sources := _terrain_sources(city, center, view)
	var street: Vector3 = sources.get("street", Vector3.ZERO)
	var overview: float = sources.get("overview", 0.0)
	var near := 1.0 - height
	_target("street", street, view, near * (1.0 - rain) * lerpf(1.0, 0.58, night))
	_target("wet_street", street, view, near * rain * lerpf(1.0, 0.58, night))
	for kind in ["shore", "river", "falls", "industry"]:
		_target(kind, sources.get(kind, Vector3.ZERO), view, near)
	_target("nature", sources.get("nature", Vector3.ZERO), view, near * lerpf(1.0, 0.15, night) * (1.0 - rain))
	var storm := weather.kind in [CityVisualWeather.Kind.RAIN_STORM, CityVisualWeather.Kind.DRY_STORM]
	var wind := height * (0.2 if storm else lerpf(1.0, 0.48, rain))
	_target("wind", Vector3(view.get_center().x, view.get_center().y, wind), view)
	_target("distant", Vector3(view.get_center().x, view.get_center().y,
		maxf(street.z * 0.7, overview) * height * (1.0 - height * 0.74)), view)

	var detail := smoothstep(0.43, 0.95, zoom)
	var crowd := Vector3.ZERO
	if detail > 0.01 and is_instance_valid(app.city_life.canvas) and app.city_life.canvas.visible:
		crowd = _figures(view, detail)
	_target("people", crowd, view, detail * lerpf(1.0, 0.30, night))
	_moving_sources(city, view, lerpf(0.26, 1.0, near))
	_place_events(sources, near)


func _terrain_sources(city: CityState, center: Vector2i, view: Rect2) -> Dictionary:
	var sources := {}
	var radius := 13
	var bounds := Rect2i(center - Vector2i.ONE * radius, Vector2i.ONE * (radius * 2 + 1)) \
		.intersection(Rect2i(Vector2i.ZERO, Vector2i.ONE * city.map_size))
	for x in range(bounds.position.x, bounds.end.x):
		for y in range(bounds.position.y, bounds.end.y):
			var point := Vector2i(x, y)
			var terrain := IsometricGeometry.surface_terrain_id(city, x, y)
			var building := city.building_id(x, y)
			if terrain == TerrainTileIds.WATERFALL:
				_offer(sources, "falls", _tile_position(city, point, -0.65), 1.0, view, 295.0)
			elif terrain >= TerrainTileIds.SHORE_FIRST and terrain <= TerrainTileIds.SHORE_RAISED:
				_offer(sources, "shore" if city.is_salt_water(x, y) else "river",
					_tile_position(city, point), 0.85, view, 265.0)
			elif terrain >= TerrainTileIds.SURFACE_WATER_NES and terrain <= TerrainTileIds.SURFACE_WATER_POND:
				_offer(sources, "shore" if city.is_salt_water(x, y) else "river",
					_tile_position(city, point), 0.68, view, 230.0)
			if building == BuildingTileIds.PIER or building == BuildingTileIds.SEAPORT_WAREHOUSE:
				_offer(sources, "shore", _tile_position(city, point), 0.76, view, 275.0)
			elif building == BuildingTileIds.STADIUM:
				_offer(sources, "stadium", _tile_position(city, point), 1.0, view, 240.0)
			elif building == BuildingTileIds.SMALL_PARK or building == BuildingTileIds.BIG_PARK \
					or building in range(BuildingTileIds.TREE_FIRST, BuildingTileIds.TREE_LAST + 1):
				_offer(sources, "nature", _tile_position(city, point), 0.74, view, 260.0)
			elif _industrial(building):
				_offer(sources, "industry", _tile_position(city, point), 0.84, view, 270.0)
			elif building != 0 and CityLifePaths.ports(city, point) != 0:
				var traffic := clampf(city.traffic_density(x, y) / 120.0, 0.0, 1.0)
				_offer(sources, "street", _tile_position(city, point), 0.13 + traffic * 0.87, view, 305.0)

	if height > 0.05:
		# A fixed-size grid covers the surrounding city even when the whole map fits.
		var edge := city.map_size
		var radius_far := clampi(roundi(view.size.x / 44.0), 14, edge)
		var step := maxi(3, roundi(radius_far / 7.0))
		var built := 0.0
		var samples := 0
		for x in range(maxi(0, center.x - radius_far), mini(edge, center.x + radius_far + 1), step):
			for y in range(maxi(0, center.y - radius_far), mini(edge, center.y + radius_far + 1), step):
				var building := city.building_id(x, y)
				if building >= BuildingTileIds.LOWER_CLASS_HOMES_1X1_1:
					built += 1.0
				samples += 1
		sources["overview"] = clampf(built / maxf(1.0, samples) * 3.0, 0.0, 1.0)
	return sources


func _figures(view: Rect2, detail: float) -> Vector3:
	var crowd := Vector3.ZERO
	var people := 0.0
	var closest_car: CityLifeController.Figure
	var closest_walker: CityLifeController.Figure
	var car_score := 0.0
	var walker_score := 0.0
	for figure in app.city_life.figures:
		var score := _distance_gain(view, figure.position, 220.0) * figure.opacity()
		if score < 0.05:
			continue
		if figure.walking:
			people += score
			if score > walker_score:
				walker_score = score
				closest_walker = figure
		elif figure.wait <= 0.0 and score > car_score:
			car_score = score
			closest_car = figure

	if closest_walker != null:
		crowd = Vector3(closest_walker.position.x, closest_walker.position.y, clampf(people / 5.0, 0.0, 1.0))
		if walker_score > 0.36 and closest_walker.wait <= 0.0:
			var step := "step_1" if random.randf() < 0.5 else "step_2"
			_shot(step, "step", closest_walker.position, 0.19 * detail * lerpf(1.0, 0.55, night),
				165.0, random.randf_range(3.0, 6.0), closest_walker)
	if closest_car != null and car_score > 0.23:
		var kind := "bus" if closest_car.vehicle_kind == CityLifeSprites.Vehicle.BUS else \
			("car_wet" if rain > 0.25 else ("car_1" if random.randf() < 0.55 else "car_2"))
		_shot(kind, "car", closest_car.position, 0.25 * detail, 265.0, random.randf_range(4.5, 8.5), closest_car)
	return crowd


func _moving_sources(city: CityState, view: Rect2, strength: float) -> void:
	if not app.view_state.show_vehicles:
		return
	var speed := app.simulation_state.speed_controller
	if speed != null and speed.speed == GameSpeedController.Speed.PAUSED:
		return
	var tracks := app.moving_sprites.traffic_motion.tracks
	for record: int in tracks:
		var track: CityTrafficMotion.Track = tracks[record]
		var kind: String = {
			Sc2ThingLayout.Type.TRAIN_ENGINE: "train", Sc2ThingLayout.Type.SHIP: "ship",
			Sc2ThingLayout.Type.AIRPLANE: "jet"
		}.get(track.type, "")
		if kind.is_empty():
			continue
		var position := _track_position(city, track)
		var reach := 610.0 if kind == "jet" else 425.0
		if _distance_gain(view, position, reach) > 0.28:
			_shot(kind, kind, position, 0.30 * strength, reach, 22.0, null, record)


func _place_events(sources: Dictionary, near: float) -> void:
	var shore: Vector3 = sources.get("shore", Vector3.ZERO)
	var stadium: Vector3 = sources.get("stadium", Vector3.ZERO)
	if elapsed >= next_wave and shore.z > 0.36 and near > 0.45:
		var wave := "wave_1" if random.randf() < 0.5 else "wave_2"
		_shot(wave, "wave", Vector2(shore.x, shore.y), 0.10, 250.0, 9.0)
		next_wave = elapsed + random.randf_range(11.0, 21.0)
	if elapsed >= next_gull and shore.z > 0.30 and night < 0.65 and rain < 0.3 and near > 0.35:
		_shot("gull", "gull", Vector2(shore.x, shore.y), 0.19, 300.0, 27.0)
		next_gull = elapsed + random.randf_range(27.0, 59.0)
	if elapsed >= next_cheer and stadium.z > 0.45 and night < 0.55 and near > 0.42:
		_shot("cheer", "stadium", Vector2(stadium.x, stadium.y), 0.27, 295.0, 52.0)
		next_cheer = elapsed + random.randf_range(53.0, 110.0)


func _shot(kind: String, key: String, position: Vector2, gain: float, reach: float,
		cooldown: float, figure: CityLifeController.Figure = null, record := -1) -> void:
	if shots.size() >= MAX_SHOTS or elapsed < source_cooldown.get(key, 0.0):
		return
	var voice := _voice(kind, false, NEAR_BUS if height < 0.44 else FAR_BUS)
	if voice == null:
		return
	voice.position = position
	voice.strength = gain
	voice.reach = reach
	voice.figure = figure
	voice.record = record
	voice.player.pitch_scale = random.randf_range(0.94, 1.06)
	voice.player.play()
	shots.append(voice)
	source_cooldown[key] = elapsed + cooldown


func _target(kind: String, candidate: Vector3, view: Rect2, factor := 1.0) -> void:
	var voice: Voice = beds.get(kind)
	if voice == null:
		return
	voice.target = candidate.z * voice.strength * factor
	voice.target_pan = _pan(view, Vector2(candidate.x, candidate.y)) if candidate.z > 0.0 else voice.pan


static func _offer(sources: Dictionary, kind: String, position: Vector2, gain: float,
		view: Rect2, reach: float) -> void:
	var score := gain * _distance_gain(view, position, reach)
	var previous: Vector3 = sources.get(kind, Vector3.ZERO)
	if score > previous.z:
		sources[kind] = Vector3(position.x, position.y, score)


static func _listening_area(map: CityMapControl) -> Rect2:
	var size := map.visible_source_rect().size
	return Rect2(map.source_center - size * 0.5, size)


static func _distance_gain(view: Rect2, position: Vector2, reach: float) -> float:
	var offset := position - view.get_center()
	offset.y *= 1.55
	return 1.0 - smoothstep(30.0, reach, offset.length())


static func _pan(view: Rect2, position: Vector2) -> float:
	return clampf((position.x - view.get_center().x) / maxf(view.size.x * 0.40, 70.0), -1.0, 1.0)


static func _tile_position(city: CityState, point: Vector2i, elevation_offset := 0.0) -> Vector2:
	return Vector2(48 + (city.map_size + point.x - point.y) * 16,
		520 + (point.x + point.y) * 8 - (city.object_altitude(point.x, point.y) + elevation_offset) * 12.0)


static func _track_position(city: CityState, track: CityTrafficMotion.Track) -> Vector2:
	return Vector2(48 + city.map_size * 16 + track.current.x, 520 + track.current.y - track.current.z)


static func _industrial(building: int) -> bool:
	return (building >= BuildingTileIds.INDUSTRIAL_1X1_FIRST and building <= BuildingTileIds.INDUSTRIAL_1X1_LAST) \
		or (building >= BuildingTileIds.INDUSTRIAL_2X2_FIRST and building <= BuildingTileIds.INDUSTRIAL_2X2_LAST) \
		or (building >= BuildingTileIds.INDUSTRIAL_3X3_FIRST and building <= BuildingTileIds.INDUSTRIAL_3X3_LAST)


class Voice extends RefCounted:
	var player: AudioStreamPlayer2D
	var position := Vector2.ZERO
	var gain := 0.0
	var target := 0.0
	var pan := 0.0
	var target_pan := 0.0
	var strength := 0.0
	var reach := 0.0
	var figure: CityLifeController.Figure
	var record := -1
