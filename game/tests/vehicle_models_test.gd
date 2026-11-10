extends SceneTree
## Rigid poses, real wheel contacts, cable supports and display-only application integration.
const State = preload("res://tests/support/document_state.gd")
const QuarterFixture = preload("res://tests/quarter_terrain_test.gd")
const MovingFixture = preload("res://tests/support/moving_surface_checks.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pack := FixtureGraphics.pack()
	var models := VehicleModels.new()
	var rasters := 0
	for kind in VehicleModels.Kind.size():
		for direction in 8:
			var forward := CityLifePaths.forward(direction)
			var flat := VehicleModels.geometry(kind,forward,0)
			for rise in [-12.0,6.0,12.0]:
				var slope := VehicleModels.geometry(kind,forward,rise)
				for part in flat.parts.size():
					var a: Vector3 = flat.parts[part].vertices[0]*Vector3(32,32,1)
					var b: Vector3 = flat.parts[part].vertices[2]*Vector3(32,32,1)
					var c: Vector3 = slope.parts[part].vertices[0]*Vector3(32,32,1)
					var d: Vector3 = slope.parts[part].vertices[2]*Vector3(32,32,1)
					assert(is_equal_approx(a.distance_to(b),c.distance_to(d)),"Pitch must preserve rigid body dimensions")
		for direction in 8:
			for divisor in [1,2,4]:
				var frame := models.frame(kind,1,CityLifePaths.forward(direction),12,pack.palette,divisor)
				assert(not frame.image.is_invisible())
				assert(frame.image.get_size()==frame.indexed.get_size() and frame.image.get_size()==frame.lamps.get_size())
				assert(frame.image.get_width()<=32 and frame.image.get_height()<=32,"Models must fit the persistent vehicle atlas")
				assert(models.frame(kind,1,CityLifePaths.forward(direction),12,pack.palette,divisor)==frame,"Unchanged poses share their raster")
				rasters+=1
	for mask in [5,10,15]:
		var parts := NetworkModelGeometry.power_routes(mask,PackedFloat32Array([0,0,0,0]))
		for direction in 4:
			if not mask & (1<<direction):
				continue
			var forward: Vector2 = NetworkModelGeometry.STEPS[direction]
			var across := Vector2(-forward.y,forward.x).normalized()*.2
			for sign_value in [-1,1]:
				var mount := Vector3(across.x*sign_value,across.y*sign_value,8)
				assert(parts.any(func(part: Dictionary) -> bool:
					if part.role!="crossarm":
						return false
					var bounds:=AABB(part.vertices[0],Vector3.ZERO)
					for vertex: Vector3 in part.vertices:
						bounds=bounds.expand(vertex)
					return bounds.grow(.0001).has_point(mount)),"Each cable must rest on a transverse arm")
	var city := QuarterFixture.fixture()
	var point := Vector2i(20,20)
	QuarterFixture.set_corners(city,point,[8,12,12,8])
	assert(is_equal_approx(VehicleModels.rise_at(city,Vector2(point),Vector2.RIGHT),12))
	assert(is_equal_approx(VehicleModels.rise_at(city,Vector2(point),Vector2.LEFT),-12))
	var before := State.capture(city.document)
	VehicleModels.contact(city,Vector2(point))
	assert(before==State.capture(city.document),"Pose evaluation cannot change a city or its RNG")
	var geometry := CityLifeGeometry.new()
	geometry.sync(city)
	QuarterFixture.set_corners(city,Vector2i(25,25),[1,1,1,1])
	assert(geometry.sync(city).has(Vector2i(25,25)),"A sub-level edit must invalidate vehicle geometry even when ALTM stays unchanged")
	var water_tile:=Vector2i(31,31)
	city.set_water_altitude(water_tile.x,water_tile.y,2)
	city.set_tile_flag(water_tile.x,water_tile.y,Sc2TileFlags.WATER,true)
	var surface:=CityStaticCommand.new()
	surface.sprite_id=1270
	surface.depth_order=(water_tile.x+water_tile.y)*city.map_size+water_tile.y
	assert(CitySurfaceOcclusion.maximum_height(city,surface)==2.0,"Quarter geometry must retain the actual water receiver height")
	var shared:=VehicleModels.new()
	shared.frame(VehicleModels.Kind.ENGINE,0,Vector2.RIGHT,6,pack.palette)
	shared.frame(VehicleModels.Kind.COACH,0,Vector2.RIGHT,6,pack.palette)
	assert(shared.meshes.size()==1,"Engines and coaches share one structural model")
	await _check_application()
	print("PASS: rigid poses in eight directions, %d native rasters, transverse cable mounts, quarter invalidation and actual application models"%rasters)
	quit()


func _check_application() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	preload("res://tests/support/app_fixture.gd").configure(main,true)
	root.add_child(main)
	await process_frame
	main.main_menu.city_background.set_process(false)
	var city := QuarterFixture.fixture()
	for x in range(18,24):
		for y in range(19,22):
			QuarterFixture.set_corners(city,Vector2i(x,y),[8+(x-18)*2,10+(x-18)*2,10+(x-18)*2,8+(x-18)*2])
		city.set_building_id(x,20,45)
		city.set_building_id(x,21,30)
	MovingFixture.write_thing(city,1,{"type":10,"x":20,"y":20,"direction":1})
	assert(main.city_session.activate_document(city.document))
	main.frame.select_speed(GameSpeedController.Speed.PAUSED)
	main.preferences.visual_enhancements.models_enabled=true
	main.visual_environment.configure()
	main.map_view.center_on_tile(Vector2i(20,20))
	await preload("res://tests/support/app_fixture.gd").wait_for_visuals(main)
	var before := State.capture(main.document_state.city.document)
	main.moving_sprites.refresh_moving_things()
	assert(not main.moving_sprites.vehicle_models.frames.is_empty(),"An actual train command must use the rigid model renderer")
	var figure := CityLifeController.Figure.new()
	figure.tile=Vector2i(20,21)
	figure.enter=3
	figure.exit=1
	figure.direction=1
	figure.progress=.5
	figure.visibility=1
	figure.position=CityLifePaths.point(main.document_state.city,figure.tile,3,1,.5,false)
	var canvas := CityLifeCanvas.new()
	canvas.gpu_enabled=false
	root.add_child(canvas)
	assert(canvas.render(main,[figure],CityLifeSprites.new()))
	assert(not canvas.vehicle_models.frames.is_empty(),"Actual road figures must use the Models setting")
	assert(canvas._sprite_sizes.is_empty(),"Generated image lifetime belongs only to the bounded model pool")
	assert(before==State.capture(main.document_state.city.document),"Model publication must preserve city and simulation state")
	main.preferences.visual_enhancements.models_enabled=false
	main.moving_sprites.vehicle_models.frames.clear()
	canvas.vehicle_models.frames.clear()
	main.moving_sprites.refresh_moving_things()
	assert(canvas.render(main,[figure],CityLifeSprites.new()))
	assert(main.moving_sprites.vehicle_models.frames.is_empty() and canvas.vehicle_models.frames.is_empty(),"Models off must restore the existing train and road artwork")
	canvas.free()
	main.queue_free()
	await process_frame
