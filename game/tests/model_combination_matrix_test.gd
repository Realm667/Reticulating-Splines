extends SceneTree
## Finite geometry/raster state space. Native tests independently cover painter selection.
@warning_ignore_start("integer_division")
const Q = preload("res://tests/quarter_terrain_test.gd")
const State = preload("res://tests/support/document_state.gd")
var geometry_cases := 0
var raster_cases := 0


func _initialize() -> void:
	_run.call_deferred()


static func planes() -> Array[PackedFloat32Array]:
	var result: Array[PackedFloat32Array]=[]
	for du in range(-4,5):
		for dv in range(-4,5):
			if absi(du)+absi(dv)>4:
				continue
			var raw := PackedFloat32Array([0,du,du+dv,dv])
			var base := minf(minf(raw[0],raw[1]),minf(raw[2],raw[3]))
			for i in 4:
				raw[i]=(raw[i]-base)*3
			result.append(raw)
	assert(result.size()==41)
	return result


func _check(recipe: Dictionary) -> void:
	assert(not recipe.parts.is_empty())
	for part: Dictionary in recipe.parts:
		for p: Vector3 in part.vertices:
			assert(p.is_finite())
		for index: int in part.indices:
			assert(index>=0 and index<part.vertices.size())
	geometry_cases+=1


func _raster(recipe: Dictionary, palette: Sc2Palette, id: int) -> void:
	for view in 3:
		var image := Image.create(32,64,false,Image.FORMAT_RGBA8)
		var raster := NetworkModelRaster.render(id,image,palette,view,recipe)
		assert(not raster.image.is_invisible(),"Empty model: %d, view %d"%[id,view])
		var pixels: PackedInt32Array=raster.entry.decode_indices().pixels
		assert(pixels.size()==raster.image.get_width()*raster.image.get_height())
		assert(raster.height.size()==pixels.size())
		for i in pixels.size():
			if pixels[i]>=0:
				assert(pixels[i]<256 and is_finite(raster.height[i]))
		raster_cases+=1


func _run() -> void:
	var pack := FixtureGraphics.pack()
	var shapes := planes()
	await _integration(pack)
	for id in range(14,112):
		for corners: PackedFloat32Array in shapes:
			for phase in 4:
				var actual := corners.duplicate()
				for k in 4:
					actual[k]=actual[k]*(2 if id in range(97,108) else 1)+phase*3
				for flip in [false,true]:
					_check(NetworkModelGeometry.build(id,actual,flip))
				var recipe := NetworkModelGeometry.build(id,actual)
				_raster(recipe,pack.palette,id)
		if id%10==0:
			print("MATRIX: surface IDs through ",id)
	var materials := UndergroundModels.materials(pack.palette)
	var underground: Array=range(305,354)
	underground.append_array(range(450,467))
	underground.append(467)
	for id: int in underground:
		for corners: PackedFloat32Array in shapes:
			for phase in 4:
				var actual := corners.duplicate()
				for k in 4:
					actual[k]+=phase*3
				var recipe := UndergroundModels.geometry(id,actual)
				recipe.materials=materials
				_check(recipe)
				_raster(recipe,pack.palette,0)
	# Terrain-independent tunnels also render beneath steep and irregular ground.
	# All routes compose the same arms; crosses exercise every arm on every shape.
	for encoded in 6561:
		var corners := PackedFloat32Array()
		for k in 4:
			corners.append(((encoded/int(pow(9,k)))%9)*3.0)
		for id in [305,334,348,464,349,350,352,353]:
			_check(UndergroundModels.geometry(id,corners))
	print("PASS: %d geometry states, %d native raster states; all 98 surface IDs, 41 normal-or-gentler planes, both mirrors, three artwork sizes and underground/service forms"%[geometry_cases,raster_cases])
	quit()


func _integration(pack: GraphicsPack) -> void:
	var city := Q.fixture()
	for x in range(8,44):
		var tile := Vector2i(x,20)
		Q.set_corners(city,tile,[9,11,11,9])
		city.set_underground_id(x,20,x-8)
		city.set_tile_flag(x,20,Sc2TileFlags.PIPED,true)
		city.set_tile_flag(x,20,Sc2TileFlags.WATERED,(x&1)==0)
	var before := State.capture(city.document)
	for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
		CityNetworkModels.configure(archive,pack.palette,true)
	for turn in 4:
		for view in 3:
			var archive := pack.large_sprites if view==2 else pack.small_medium_sprites
			var context := CityGpuBuildContext.new()
			for layers in (range(16) if turn==0 and view==2 else [15]):
				assert(context.prepare(city,Sc2Palette.index_encoding(),archive,view,CityViewMode.Mode.UNDERGROUND,layers&1!=0,layers&2!=0,layers&4!=0,0,false,false,0,layers&8!=0).is_empty())
				_assert_model_images(context,city)
		assert(CityRotationCommand.apply(city,true).ok)
	assert(State.capture(city.document)==before,"Four rotations and model preparation must preserve saved state")
	var old_signature := CityUndergroundView.visual_signature(city,2)
	var old_data := CityDataView.geometry_signature(city)
	Q.set_corners(city,Vector2i(20,20),[10,12,12,10])
	assert(old_signature!=CityUndergroundView.visual_signature(city,2))
	assert(old_data!=CityDataView.geometry_signature(city))
	var image := CityDataView.value_image(city,CityViewMode.Mode.HEIGHT)
	assert(image.get_format()==Image.FORMAT_RF)
	assert(is_equal_approx(image.get_pixel(20,20).r,2.75))
	assert(CityDataView.tile_text(city,CityViewMode.Mode.HEIGHT,Vector2i(20,20)).contains("2.75"))
	for mode: String in CityMinimap.MODES:
		assert(CityMinimap.create_image(city,pack.palette,mode).get_size()==Vector2i(64,64))
	print("PASS: actual underground builders in 12 layouts, quarter cache invalidation, float height values and all 18 minimap modes")


func _assert_model_images(context: CityGpuBuildContext, city: CityState) -> void:
	assert(context.builder.missing_sprites().is_empty())
	assert(not context.underground_models.cache.is_empty())
	var modeled := {}
	for item: Dictionary in context.underground_models.cache.values():
		var image: Image=item.entry.create_image(Sc2Palette.index_encoding()).image
		modeled[var_to_bytes([image.get_size(),image.get_data()]).hex_encode()]=true
	var points: Array[Vector2i]=[]
	for i in city.underground.size():
		if city.underground[i]>0:
			points.append(Vector2i(i/city.map_size,i%city.map_size))
	var drawn := context.tile_draws(points)
	for image: Image in drawn.images:
		assert(modeled.has(var_to_bytes([image.get_size(),image.get_data()]).hex_encode()),"Native profile and prepared geometry disagree; sprite fallback concealed a join or hidden-layer error")
