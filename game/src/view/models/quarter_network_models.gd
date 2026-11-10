class_name QuarterNetworkModels
extends RefCounted
## Worker-owned variants of the shared network recipes at actual corner heights.
@warning_ignore_start("integer_division")

var cache: Dictionary = {}
var material_signature := ""
var next_id := 1000000000


func prepare(city: CityState,archive: Sc2SpriteArchive,palette: Sc2Palette,view: int) -> Dictionary:
	var ids:=PackedInt32Array()
	ids.resize(city.map_size*city.map_size)
	var images: Dictionary[int,Image]={}
	var design: Sc2Palette=archive.network_model_palette if archive.network_model_palette!=null else palette
	var signature:=design.to_rgba_bytes().hex_encode().sha256_text()+str(view)
	if signature!=material_signature or cache.size()>1024:
		cache.clear()
		material_signature=signature
	var library:=NetworkModelGeometry.Library.new(NetworkModelGeometry.build,NetworkModelGeometry.template)
	for i in city.buildings.size():
		var id:=int(city.buildings[i])
		var debris := id in range(1,5)
		if (not debris and (id<14 or id>111)) or id in range(81,93) or id in [106,107] or city.is_water(i/city.map_size,i%city.map_size):
			continue
		if debris and not archive.network_model_entries.has(view*500+id):
			continue
		var tile:=Vector2i(i/city.map_size,i%city.map_size)
		var base:=city.land_altitude(tile.x,tile.y)*4
		var corners:=PackedFloat32Array()
		if id in range(97,108):
			# The native composite anchor is the SW tile of its 2x2 footprint.
			for sample in [Vector3i(0,-1,0),Vector3i(1,-1,1),Vector3i(1,0,2),Vector3i(0,0,3)]:
				var cell:=city.index_of(tile.x+sample.x,tile.y+sample.y)
				var q:=city.quarter_heights[cell*4+sample.z] if cell>=0 else base
				corners.append((q-base)*3.0)
		else:
			for k in 4:
				corners.append((city.quarter_heights[i*4+k]-base)*3.0)
		var flip:=city.is_flipped(tile.x,tile.y)
		if flip:
			corners=PackedFloat32Array([corners[0],corners[3],corners[2],corners[1]])
		var key:=var_to_bytes([id,corners]).hex_encode()
		if not cache.has(key):
			var model: Dictionary=library.acquire(id,corners)
			var recipe: Dictionary={"parts":model.mesh.parts,"footprint":model.footprint,"ports":model.ports}
			var source:=archive.entries_by_id.get(view*500+id) as Sc2SpriteArchive.SpriteEntry
			if source==null:
				continue
			var material:=Image.create(source.width,source.height,false,Image.FORMAT_RGBA8)
			var rendered:=NetworkModelRaster.render(id,material,design,view,recipe)
			var entry: Sc2SpriteArchive.SpriteEntry=rendered.entry
			entry.sprite_id=next_id
			next_id+=1
			cache[key]=entry
		var entry: Sc2SpriteArchive.SpriteEntry=cache[key]
		ids[i]=entry.sprite_id
		if not images.has(entry.sprite_id):
			images[entry.sprite_id]=entry.create_image(palette).image
	return {"ids":ids,"images":images}
