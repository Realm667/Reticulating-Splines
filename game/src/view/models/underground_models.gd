class_name UndergroundModels
extends RefCounted
## Shared cutaway tubes and service frames. Simulation connectivity stays in XUND.
@warning_ignore_start("integer_division")
const G = preload("res://src/view/models/network_model_geometry.gd")
const PORTS := G.PORTS
const BASELINE := 45
const TUNNEL_RADIUS := 6.5
const COLORS := {"frame":"9b8747","service":"007700","water":"00bf00",
	"tube":"007700","cut":"777777","rail":"b7b7b7","sleeper":"282828",
	"dry_pipe":"171717","wet_pipe":"0000df","rim":"00bfbf","silo":"777777"}
var cache: Dictionary = {}
var signature := ""
var next_id := 1100000000
var swatches: Dictionary = {}


static func corners(city: CityState, i: int) -> PackedFloat32Array:
	var base := city.land_altitude(i/city.map_size,i%city.map_size)*4
	var result := PackedFloat32Array()
	if not city.quarter_heights.is_empty():
		for k in 4:
			result.append((city.quarter_heights[i*4+k]-base)*3.0)
	else:
		var shape := int(city.terrain[i])&15 if int(city.terrain[i])<0x30 else 0
		var mask: int=IsometricConstants.TERRAIN_SURFACE_CORNER_MASKS[shape] if shape<15 else 0
		for k in 4:
			result.append(12.0 if mask&(1<<k) else 0.0)
	return result


static func absolute_corners(city: CityState, i: int) -> PackedInt32Array:
	if not city.quarter_heights.is_empty():
		return city.quarter_heights.slice(i*4,i*4+4)
	var result := PackedInt32Array()
	var base := city.land_altitude(i/city.map_size,i%city.map_size)*4
	for z: float in corners(city,i):
		result.append(base+roundi(z/3))
	return result


static func profile(city: CityState, i: int) -> PackedFloat32Array:
	var tile := Vector2i(i/city.map_size,i%city.map_size)
	var neighbors := PackedInt32Array()
	var types := PackedInt32Array()
	for step: Vector2i in CityLifePaths.DIRECTIONS:
		var n := city.index_of(tile.x+step.x,tile.y+step.y)
		neighbors.append_array(absolute_corners(city,n) if n>=0 else PackedInt32Array([0,0,0,0]))
		types.append(int(city.underground[n]) if n>=0 else 0)
	var encoded := NativeCityDataMesh.underground_profile(city.land_altitude(tile.x,tile.y),int(city.underground[i]),absolute_corners(city,i),neighbors,types)
	assert(encoded.size()==13)
	var result := PackedFloat32Array()
	for value: int in encoded:
		result.append(value/4.0)
	return result


func prepare(city: CityState, palette: Sc2Palette, view: int, design: Sc2Palette) -> Dictionary:
	var stamp := design.to_rgba_bytes().hex_encode().sha256_text()+str(view)
	if stamp!=signature or cache.size()>2048:
		cache.clear()
		signature=stamp
		swatches=materials(design)
	var replacements := PackedInt64Array()
	var images: Dictionary[int,Image] = {}
	for i in city.altitude_words.size():
		var heights := profile(city,i)
		var ids := [305,351,467,352]
		var tile := int(city.underground[i])
		if tile>0 and tile<=35:
			ids.append(318+tile)
			if tile>=16 and tile<=32:
				ids.append(318+tile+116)
		if tile in [31,32]:
			ids.append(319 if tile==31 else 320)
			var pipe_only := 335 if tile==31 else 334
			ids.append(pipe_only)
			ids.append(pipe_only+116)
		# Original wireframe and one-level road-tunnel IDs vary by XTER shape.
		var t := int(city.terrain[i])
		var wire := 305+mini(t&15,13) if t<=14 or t in range(16,31) or t in range(32,47) else 305
		ids[0]=wire
		var levels := (city.altitude_words[i]>>10)&31
		if levels==1:
			ids.append(62+t)
		for id: int in ids:
			var key := var_to_bytes([id,heights]).hex_encode()
			if not cache.has(key):
				var recipe := geometry(id,heights)
				recipe.materials=swatches
				var divisor := 4>>view
				var source := Image.create(32/divisor,ceili((float(recipe.baseline)+8)/divisor),false,Image.FORMAT_RGBA8)
				var raster := NetworkModelRaster.render(0,source,design,view,recipe)
				var entry: Sc2SpriteArchive.SpriteEntry=raster.entry
				entry.sprite_id=next_id
				next_id+=1
				cache[key]={"entry":entry,"baseline":recipe.baseline}
			var entry: Sc2SpriteArchive.SpriteEntry=cache[key].entry
			if not images.has(entry.sprite_id):
				replacements.append(view*500+id)
				for height: float in heights:
					replacements.append(roundi(height*4))
				replacements.append_array(PackedInt64Array([entry.sprite_id,int(cache[key].baseline)]))
				images[entry.sprite_id]=entry.create_image(palette).image
	return {"replacements":replacements,"images":images}


static func materials(palette: Sc2Palette) -> Dictionary:
	var result := {}
	for role: String in COLORS:
		var color := Color(COLORS[role])
		result[role]=PackedInt32Array([NetworkModelRaster.nearest(palette,color),
			NetworkModelRaster.nearest(palette,color.lightened(.22)),NetworkModelRaster.nearest(palette,color.darkened(.3))])
	result.deck=result.frame
	return result


static func geometry(sprite: int, heights: PackedFloat32Array) -> Dictionary:
	var parts: Array = []
	var points := PackedVector3Array()
	for k in 4:
		var p: Vector2=[Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5)][k]
		points.append(Vector3(p.x,p.y,heights[k]))
	var service := sprite in [351,467]
	for k in 4:
		G.beam(parts,"water" if sprite==467 else ("service" if service else "frame"),points[k],points[(k+1)%4],.7)
	var tile := sprite-318
	var watered := tile>=132 and tile<=148
	if watered:
		tile-=116
	var subway_ends := heights.slice(4,8) if heights.size()>=12 else PackedFloat32Array()
	var pipe_ends := heights.slice(8,12) if heights.size()>=12 else PackedFloat32Array()
	var pipe_depth := heights[12] if heights.size()==13 else (-24.0 if tile in [31,32] else -12.0)
	if tile>=1 and tile<=15:
		routes(parts,PORTS[tile-1],heights,false,false,-12,subway_ends)
	elif tile>=16 and tile<=30:
		routes(parts,PORTS[tile-16],heights,true,watered,pipe_depth,pipe_ends)
	elif tile in [31,32]:
		routes(parts,5 if tile==31 else 10,heights,false,false,-12,subway_ends)
		routes(parts,10 if tile==31 else 5,heights,true,watered,pipe_depth,pipe_ends)
	elif tile==35:
		routes(parts,15,heights,false,false,-12,subway_ends)
		var top := G.surface_height(Vector2.ZERO,heights)
		G.box(parts,"silo",Vector3(-.16,-.16,-12),Vector3(.16,.16,top))
		for step in 3:
			G.box(parts,"rail",Vector3(-.165,-.165,top-step*4-1),Vector3(.165,.165,top-step*4-.5))
	elif tile==34:
		G.box(parts,"silo",Vector3(-.24,-.24,-24),Vector3(.24,.24,-1))
	elif sprite==352 or sprite in range(62,126):
		routes(parts,10 if sprite==352 else 5,heights,false,false,-24)
	var baseline := BASELINE
	for part: Dictionary in parts:
		for vertex: Vector3 in part.vertices:
			baseline=maxi(baseline,ceili(G.project(vertex).y)+1)
	return {"parts":parts,"ports":0,"footprint":1,"baseline":baseline}


static func routes(parts: Array, mask: int, heights: PackedFloat32Array, pipe: bool, watered: bool, depth := -12.0, ends := PackedFloat32Array()) -> void:
	var center := Vector3(0,0,G.surface_height(Vector2.ZERO,heights)+depth)
	for k in 4:
		if not mask&(1<<k):
			continue
		var p: Vector2=G.STEPS[k]
		var end := Vector3(p.x,p.y,ends[k] if ends.size()==4 else G.surface_height(p,heights)+depth)
		var across := Vector3(-p.y,p.x,0).normalized()
		if pipe:
			tube(parts,"wet_pipe" if watered else "dry_pipe",center,end,1.1)
			tube(parts,"rim",end,end-(end-center)*.04,1.35)
		else:
			# Open upper half exposes track and vehicles; the rear shell remains spatial.
			tube(parts,"cut",center,end,TUNNEL_RADIUS,true)
			# The back quarter of the green shell keeps the original tunnel silhouette.
			# Its open front quarter exposes the shared train bodies and the rails.
			var axis := Vector2(end.x-center.x,end.y-center.y).normalized()
			var normal := Vector3(-axis.y/32,axis.x/32,0)
			for segment in 4:
				var angle := segment*PI/4
				if cos(angle+PI/8)*(normal.x+normal.y)>0:
					continue
				var a := normal*cos(angle)*TUNNEL_RADIUS+Vector3(0,0,sin(angle)*TUNNEL_RADIUS)
				var b := normal*cos(angle+PI/4)*TUNNEL_RADIUS+Vector3(0,0,sin(angle+PI/4)*TUNNEL_RADIUS)
				G.face(parts,"tube",PackedVector3Array([center+a,end+a,end+b,center+b]))
			for sign_value in [-1,1]:
				G.beam(parts,"rail",center+across*.09*sign_value,end+across*.09*sign_value,0.7)
			for t in [.15,.45,.75]:
				var at := center.lerp(end,t)-Vector3(0,0,.6)
				G.beam(parts,"sleeper",at-across*.14,at+across*.14,1)


static func tube(parts: Array, role: String, a: Vector3, b: Vector3, radius: float, cutaway := false) -> void:
	var direction := Vector2(b.x-a.x,b.y-a.y).normalized()
	var across := Vector3(-direction.y/32,direction.x/32,0)
	for k in (4 if cutaway else 8):
		var angle := PI+k*TAU/8 if cutaway else k*TAU/8
		var next := angle+TAU/8
		var p := across*cos(angle)*radius+Vector3(0,0,sin(angle)*radius)
		var q := across*cos(next)*radius+Vector3(0,0,sin(next)*radius)
		G.face(parts,role,PackedVector3Array([a+p,b+p,b+q,a+q]))
