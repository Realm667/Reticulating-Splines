class_name TutorialTrainingCity
extends RefCounted
## Deliberately chosen starting conditions, only for an explicitly new exercise.


static func create(chapter: int) -> Sc2File:
	var random := SimRandom.new(7319)
	var game_random := GameLcgRandom.new(537)
	var founded := NewCitySetup.create(EmptyCityTemplate.create(), TranslationServer.translate("Learning City"), TranslationServer.translate("Mayor"), 1,
		2050 if chapter == 10 else 1900, random, game_random)
	if not founded.ok:
		return null
	var city := CityState.from_document(founded.document)
	city.set_no_disasters_enabled(true)
	# A flat site and a small fresh-water shore make the initial task legible.
	for x in 128:
		for y in 128:
			city.set_land_altitude(x, y, 4)
			city.set_terrain_id(x, y, TerrainTileIds.FLAT)
	for x in range(24, 31):
		for y in range(35, 80):
			city.set_land_altitude(x, y, 3)
			city.set_water_altitude(x, y, 4)
			city.set_terrain_id(x, y, TerrainTileIds.DEEP_WATER_FLAT)
			city.set_tile_flag(x, y, Sc2TileFlags.WATER, true)
	if chapter >= 2:
		var lfsr := SimLfsrRandom.new(137)
		BuildingCommand.apply(city, CityToolIds.Group.POWER, CityToolIds.Power.COAL, Vector2i(35, 45), lfsr, random)
		NetworkCommand.apply(city, CityToolIds.Group.ROADS, 0, Vector2i(40, 50), Vector2i(65, 50))
		ZoneCommand.apply_rectangle(city, CityToolIds.Group.RESIDENTIAL, 0, Vector2i(45, 47), Vector2i(52, 49))
		ZoneCommand.apply_rectangle(city, CityToolIds.Group.INDUSTRIAL, 0, Vector2i(55, 51), Vector2i(62, 53))
		if chapter != 4:
			NetworkCommand.apply(city, CityToolIds.Group.POWER, 0, Vector2i(38, 47), Vector2i(45, 47))
			NetworkCommand.apply(city, CityToolIds.Group.POWER, 0, Vector2i(38, 46), Vector2i(62, 46))
			NetworkCommand.apply(city, CityToolIds.Group.POWER, 0, Vector2i(54, 46), Vector2i(54, 52))
		if chapter >= 3:
			BuildingCommand.apply(city, CityToolIds.Group.WATER, CityToolIds.Water.PUMP, Vector2i(31, 47), lfsr, random)
			# A route cannot start inside the pump or power plant footprint.
			NetworkCommand.apply(city, CityToolIds.Group.POWER, 0, Vector2i(32, 47), Vector2i(33, 47))
			if chapter != 4:
				NetworkCommand.apply(city, CityToolIds.Group.WATER, 0, Vector2i(31, 47), Vector2i(52, 47))
		if chapter == 9:
			BuildingCommand.apply(city, CityToolIds.Group.SERVICES, CityToolIds.Services.FIRE_STATION, Vector2i(42, 54), lfsr, random)
	# Normal easy starting funds minus all regular construction prices; no gifts.
	return city.document
