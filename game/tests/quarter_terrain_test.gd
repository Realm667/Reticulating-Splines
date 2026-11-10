extends SceneTree
## Saved geometry, costs, tools and exact reversibility through public commands.
@warning_ignore_start("integer_division")
const State = preload("res://tests/support/document_state.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+message)


static func fixture() -> CityState:
	var document: Sc2File=Sc2xDocument.create_empty(64,"Quarter terrain test").document
	assert(ExpandedRules.enable(document).is_empty())
	var city:=CityState.from_document(document)
	city.set_funds(1000000)
	assert(QuarterTerrain.enable(city).is_empty())
	return city


static func set_corners(city: CityState, tile: Vector2i, values: Array) -> void:
	var chunk:=city.document.find_chunk("XQTR")
	var data:=chunk.decoded_payload.duplicate()
	var i:=city.index_of(tile.x,tile.y)
	for k in 4:
		data[16+i*8+k*2]=int(values[k])>>8
		data[17+i*8+k*2]=int(values[k])&255
	chunk.set_decoded_payload(data)
	city.resync_mirrors(["XQTR"])
	city.set_land_altitude(tile.x,tile.y,int(values.min())/4)
	var mask:=0
	for k in 4:
		if values[k]>values.min():
			mask|=1<<k
	city.set_terrain_id(tile.x,tile.y,IsometricConstants.TERRAIN_SURFACE_CORNER_MASKS.find(mask))


func _run() -> void:
	var classic:=CityState.from_document(Sc2xDocument.create_empty(64,"Classic").document)
	check(not QuarterTerrain.enable(classic).is_empty(),"Classic stays unchanged")
	var city:=fixture()
	var tile:=Vector2i(20,20)
	QuarterTerrain.configure(city,1,0)
	var random:=SimRandom.new(913)
	var before:=State.capture(city.document)
	var first:=TerrainCommand.apply_path(city,0,2,tile,[tile],random)
	check(first.ok and first.cost==6,"Quarter step charges reduced cost")
	check(is_equal_approx(QuarterTerrain.height(city,tile),.25),"Exact quarter height")
	check(random.state==913,"Quarter editing consumes no random numbers")
	check(TerrainCommand.undo(city,first,random).ok and State.capture(city.document)==before,"Undo restores all bytes and fractions")
	var changed_brush:=TerrainCommand.apply_path(city,0,2,tile,[tile])
	QuarterTerrain.configure(city,2,8)
	check(TerrainCommand.undo(city,changed_brush).ok and is_zero_approx(QuarterTerrain.height(city,tile)),"Undo survives a brush option change")
	check(city.document.find_chunk("XQTR").decoded_payload[6]==2,"Undo retains current brush settings")
	QuarterTerrain.configure(city,1,0)
	var costs:=[]
	for stroke in 4:
		costs.append(TerrainCommand.apply_path(city,0,2,tile,[tile]).cost)
	check(costs==[6,6,6,7],"Four isolated quarter steps cost exactly 25")
	check(city.funds()==999975,"Cumulative money accounting")
	var serialized:=city.document.serialize()
	var loaded:=Sc2File.new()
	check(serialized.ok and loaded.parse(serialized.data),"SC2X save and load")
	check(CityState.from_document(loaded).is_valid(),"Loaded capability validates")
	check(loaded.find_chunk("XQTR").decoded_payload==city.document.find_chunk("XQTR").decoded_payload,"Exact corner/header round trip")
	var q:=city.document.find_chunk("XQTR").decoded_payload
	for turn in 4:
		check(CityRotationCommand.apply(city,true).ok,"Quarter city rotation")
	check(city.document.find_chunk("XQTR").decoded_payload==q,"Four rotations restore corners and cost remainder")
	var dirty:=ApplicationStaticRender._edit_dirty_indices(first,city.map_size)
	check(dirty.has(city.index_of(tile.x,tile.y)),"Fractional-only edits invalidate the correct tile")
	for grade in [2,4,8]:
		var landscape:=fixture()
		QuarterTerrain.configure(landscape,8,grade)
		check(TerrainCommand.apply_path(landscape,0,2,tile,[tile]).ok,"Slope brush "+str(grade))
		var maximum:=0
		for i in landscape.map_size*landscape.map_size:
			var c:=Array(landscape.quarter_heights.slice(i*4,i*4+4))
			maximum=maxi(maximum,c.max()-c.min())
		check(maximum==grade,"Brush produces exact maximum grade "+str(grade))
	for height in [2,4,8]:
		for direction in 4:
			for group in [3,6,7]:
				var network_city:=fixture()
				var shape: Array=[8,8+height,8+height,8]
				for turn in direction:
					shape.push_back(shape.pop_front())
				set_corners(network_city,tile,shape)
				check(not ZoneCommand.apply_rectangle(network_city,9,0,tile,tile).ok,"Zones reject every slope")
				var next: Vector2i=tile+CityLifePaths.DIRECTIONS[posmod(1-direction,4)]
				set_corners(network_city,next,shape.map(func(q: int) -> int: return q+height))
				var result:=NetworkCommand.apply(network_city,group,0,tile,next)
				check(result.ok==(height<=4),"Surface network cap %d direction %d group %d: %s"%[height,direction,group,result.error])
	var level_city:=fixture()
	for height in [2,4,8]:
		for direction in 4:
			var highway_city:=fixture()
			for x in range(20,22):
				for y in range(20,22):
					var values:=[]
					for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.ONE,Vector2i.DOWN]:
						var u:=x-20+offset.x
						var v:=y-20+offset.y
						values.append(8+height*[u,v,2-u,2-v][direction])
					set_corners(highway_city,Vector2i(x,y),values)
			var original_q:=highway_city.quarter_heights.duplicate()
			var highway:=HighwayCommand.apply(highway_city,6,1,tile,tile)
			check(highway.ok==(height<=4),"Highway cap and plane %d turn %d: %s"%[height,direction,highway.error])
			check(highway_city.quarter_heights==original_q,"Highway preserves exact supporting plane")
			if height<=4:
				QuarterTerrain.configure(highway_city,1,0)
				var support_before:=State.capture(highway_city.document)
				var reshape:=TerrainCommand.apply_path(highway_city,0,2,tile,[tile])
				check(not reshape.ok and State.capture(highway_city.document)==support_before,"Existing highway supports reject grading atomically")
	set_corners(level_city,tile,[9,9,9,9])
	check(ZoneCommand.apply_rectangle(level_city,9,0,tile,tile).ok,"Zones accept fractional level ground")
	var building_city:=fixture()
	set_corners(building_city,tile,[8,10,10,8])
	check(not BuildingCommand.apply(building_city,14,0,tile,SimLfsrRandom.new(3),SimRandom.new(2)).ok,"Buildings reject gentle slopes")
	set_corners(building_city,tile,[9,9,9,9])
	check(BuildingCommand.apply(building_city,14,0,tile,SimLfsrRandom.new(3),SimRandom.new(2)).ok,"Buildings accept quarter plateaus")
	var poor:=fixture()
	QuarterTerrain.configure(poor,1,0)
	poor.set_funds(5)
	before=State.capture(poor.document)
	check(not TerrainCommand.apply_path(poor,0,2,tile,[tile]).ok and before==State.capture(poor.document),"Insufficient funds are atomic")
	var world:=SharedWorld.new()
	check(world.open(city.document),"Quarter shared-world document opens")
	var first_actor:="a".repeat(48)
	var second_actor:="b".repeat(48)
	check(world.add_player(first_actor).is_empty() and world.add_player(second_actor).is_empty(),"Both municipalities retain terrain capability")
	check(world.municipalities[second_actor].city.quarter_heights==city.quarter_heights,"Fresh municipality inherits actual corners")
	var snapshot:=world.snapshot_for(second_actor)
	check(str(snapshot.get("error","")).is_empty(),"Quarter shared snapshot composes: "+str(snapshot.get("error","")))
	check(not SharedLandTransfer.stage(city,classic,[city.index_of(tile.x,tile.y)]).get("error","").is_empty(),"Incompatible corner capabilities reject a parcel transfer")
	var checkpoint:=world.saved_shared()
	var restored_world:=SharedWorld.new()
	check(restored_world.open(city.document) and restored_world.restore_shared(checkpoint).is_empty(),"Quarter shared checkpoint restores")
	checkpoint.cities[second_actor].state.city=Marshalls.raw_to_base64(classic.document.serialize().data)
	check(not restored_world.restore_shared(checkpoint).is_empty(),"Mixed quarter and legacy municipalities rejected")
	var damaged:=loaded.duplicate_document()
	damaged.find_chunk("XQTR").set_decoded_payload(PackedByteArray([1]))
	check(not CityState.from_document(damaged).is_valid(),"Malformed corner data rejected")
	await _check_ui()
	print("Quarter terrain: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)


func _check_ui() -> void:
	var main: CityApplication=(load("res://main.tscn") as PackedScene).instantiate()
	preload("res://tests/support/app_fixture.gd").configure(main,true)
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.main_menu.city_background.set_process(false)
	var document: Sc2File=Sc2xDocument.create_empty(64,"Quarter UI").document
	check(ExpandedRules.enable(document).is_empty(),"Expanded UI fixture")
	check(main.city_session.activate_document(document),"Activate fixture")
	main.frame.select_speed(GameSpeedController.Speed.PAUSED)
	main.preferences.visual_enhancements.models_enabled=true
	main.visual_environment.configure()
	main.settings.open_settings_dialog()
	var panel:=main.main_overlays.settings_dialog.visual_tab.terrain_models_panel
	check(not panel.enable_button.disabled,"Models offers quarter terrain")
	panel.enable_button.pressed.emit()
	check(QuarterTerrain.enabled(document) and not panel.step.disabled,"Models activation updates controls")
	check(main.main_overlays.settings_dialog.visual_tab.controls.models_enabled.disabled,"Required display remains enabled")
	panel.grade.select(2)
	panel.grade.item_selected.emit(2)
	check(document.find_chunk("XQTR").decoded_payload[7]==8,"Slope selection stored with city")
	main.free()
	await process_frame
