extends "res://tests/city_gpu_geometry_test.gd"
## Shared SC2000 debris, rigid fragment poses and the real Models integration.
@warning_ignore_start("integer_division")
const Q = preload("res://tests/quarter_terrain_test.gd")
const State = preload("res://tests/support/document_state.gd")


func _run() -> void:
	var pack := FixtureGraphics.pack()
	var poses := 0
	for id in range(1,5):
		var flat := NetworkModelGeometry.build(id)
		assert(flat.family=="rubble" and flat.ports==0)
		for plane: PackedFloat32Array in preload("res://tests/model_combination_matrix_test.gd").planes():
			for phase in 4:
				var corners := plane.duplicate()
				for k in 4:
					corners[k]+=phase*3.0
				var posed := NetworkModelGeometry.build(id,corners)
				assert(posed.parts.size()==flat.parts.size())
				# The first eight faces are the loose mound. Rigid fragments retain
				# physical edge lengths while their supporting terrain plane changes.
				for part in range(8,posed.parts.size()):
					for endpoint in [1,2]:
						var before := physical(flat.parts[part].vertices[endpoint]-flat.parts[part].vertices[0]).length_squared()
						var after := physical(posed.parts[part].vertices[endpoint]-posed.parts[part].vertices[0]).length_squared()
						assert(absf(before-after)<.002,"A rubble fragment changed its rigid dimensions")
				for view in 3:
					var source := Image.create(32>>(2-view),ceili(17.0/(4>>view)),false,Image.FORMAT_RGBA8)
					var rendered := NetworkModelRaster.render(id,source,pack.palette,view,posed)
					var opaque := false
					for pixel: int in rendered.entry.decode_indices().pixels:
						opaque=opaque or pixel>=0
					assert(opaque)
					poses+=1
	for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
		CityNetworkModels.configure(archive,pack.palette,true)
		for base in ([1000] if archive==pack.large_sprites else [0,500]):
			for id in range(1,5):
				assert(archive.find_sprite(base+id)!=archive.entries_by_id[base+id])
			for id in range(5,14):
				assert(not archive.network_model_entries.has(base+id),"Retained sprite objects must stay outside the model inventory")
	var pairs := 0
	for quarter in [false,true]:
		var city := Q.fixture() if quarter else CityState.from_document(Sc2xDocument.create_empty(64,"Rubble models").document)
		for id in range(1,5):
			for grade in 5:
				var tile := Vector2i(12+id*6,12+grade*6)
				if quarter:
					Q.set_corners(city,tile,[[9,9,9,9],[9,11,11,9],[9,13,13,9],[9,17,17,9],[9,13,17,13]][grade])
				city.set_building_id(tile.x,tile.y,id)
				city.set_tile_flag(tile.x,tile.y,Sc2TileFlags.FLIPPED,grade%2==0)
		for turn in 4:
			var before := State.capture(city.document)
			for view in 3:
				var archive := pack.large_sprites if view==2 else pack.small_medium_sprites
				var context := CityGpuBuildContext.new()
				var failure := context.prepare(city,Sc2Palette.index_encoding(),archive,view)
				assert(failure.is_empty(),failure)
				if quarter:
					assert(context.quarter_models.cache.size()>=4)
				await _compare(city,Sc2Palette.index_encoding(),archive,Rect2i(Vector2i.ZERO,CityIsometricRenderer.output_size_for_view(view,64)),view,CityViewMode.Mode.CITY,context)
				pairs+=1
			assert(State.capture(city.document)==before)
			assert(CityRotationCommand.apply(city,true).ok)
	for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
		CityNetworkModels.configure(archive,pack.palette,false)
		for id: int in archive.entries_by_id:
			if id%500 in range(1,5):
				assert(archive.find_sprite(id)==archive.entries_by_id[id])
	print("PASS: %d debris rasters, rigid fragments, %d exact CPU/GPU pairs, original restoration, retained sprites and unchanged saved state"%[poses,pairs])
	quit()


static func physical(point: Vector3) -> Vector3:
	return Vector3(point.x*32.0,point.y*32.0,point.z)
