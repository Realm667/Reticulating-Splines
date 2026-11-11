class_name UndergroundModels
extends RefCounted
## Shared cutaway tubes and service frames. Simulation connectivity stays in XUND.
@warning_ignore_start("integer_division")
const G = preload("res://src/view/models/network_model_geometry.gd")
const PORTS := G.PORTS
const BASELINE := 45
const TUNNEL_RADIUS := 8.0
const TUNNEL_INNER_RADIUS := 6.5
# The painted arch exaggerates the shell width; the train bore keeps its gauge.
const TUNNEL_WIDTH_SCALE := 2.0
const LINING_LIFT := .25
const PIPE_RADIUS := 2.75
const PIPE_COLLAR_RADIUS := 3.0
# The crown catches light, while the underside and the lower opening fall into shadow.
const SHELL_FACETS := ["tube","tube_crown","tube_crown","tube",
	"tube_shade","tube_base","tube_base","tube_shade"]
const LINING_FACETS := ["lining_mid","lining_light","lining_light","lining_mid",
	"tunnel_dark","tunnel_dark","tunnel_dark","tunnel_dark"]
const COMPACT_MOUTH_FACETS := ["arch","lining_light","lining_light","arch",
	"tunnel_dark","tunnel_dark","tunnel_dark","tunnel_dark"]
const DARK_LINING_FACETS := ["tunnel_dark","tunnel_dark","tunnel_dark","tunnel_dark",
	"tunnel_dark","tunnel_dark","tunnel_dark","tunnel_dark"]
const MOUTH_ALONG_X := ["arch","lining_mid","lining_light","lining_light",
	"lining_light","lining_mid","tunnel_dark","tunnel_dark"]
const MOUTH_ALONG_Y := ["lining_light","lining_light","lining_mid","arch",
	"tunnel_dark","tunnel_dark","lining_mid","lining_light"]
const TUNNEL_COLORS := {"tube_crown":"078b00","tube_shade":"075b00","tube_base":"074300",
	"arch":"737373","lining_light":"ababab","lining_mid":"8f8f8f","tunnel_dark":"000000","subway_rail":"575757"}
const COLORS := {"frame":"9b8747","service":"007700","water":"00bf00",
	"tube":"077300","cut":"8f8f8f","lining":"000000","rail":"b7b7b7","sleeper":"282828",
	"dry_pipe":"0000b3","wet_pipe":"0000df","rim":"00bfbf","silo":"777777"}
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
				# The eight-pixel glyph needs the original compact section to keep its pixel phase.
				var recipe := geometry(id,heights,view==0)
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
	result.tube=PackedInt32Array([NetworkModelRaster.nearest(palette,Color("077300")),
		NetworkModelRaster.nearest(palette,Color("078b00")),NetworkModelRaster.nearest(palette,Color("074300"))])
	result.tube_dither=PackedInt32Array([NetworkModelRaster.nearest(palette,Color("075b00")),
		NetworkModelRaster.nearest(palette,Color("077300")),NetworkModelRaster.nearest(palette,Color("075b00"))])
	result.lining=PackedInt32Array([NetworkModelRaster.nearest(palette,Color("000000")),
		NetworkModelRaster.nearest(palette,Color("8f8f8f")),NetworkModelRaster.nearest(palette,Color("575757"))])
	for role: String in TUNNEL_COLORS:
		var index := NetworkModelRaster.nearest(palette,Color(TUNNEL_COLORS[role]))
		result[role]=PackedInt32Array([index,index,index])
	return result


static func geometry(sprite: int, heights: PackedFloat32Array, compact := false) -> Dictionary:
	var parts: Array = []
	var points := PackedVector3Array()
	for k in 4:
		var p: Vector2=[Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5)][k]
		points.append(Vector3(p.x,p.y,heights[k]))
	var service := sprite in [351,467]
	for k in 4:
		G.beam(parts,"water" if sprite==467 else ("service" if service else "frame"),points[k],points[(k+1)%4],1.4)
	var tile := sprite-318
	var watered := tile>=132 and tile<=148
	if watered:
		tile-=116
	var subway_ends := heights.slice(4,8) if heights.size()>=12 else PackedFloat32Array()
	var pipe_ends := heights.slice(8,12) if heights.size()>=12 else PackedFloat32Array()
	var pipe_depth := heights[12] if heights.size()==13 else 0.0
	if tile>=1 and tile<=15:
		routes(parts,PORTS[tile-1],heights,false,false,-12,subway_ends,true,compact)
	elif tile>=16 and tile<=30:
		routes(parts,PORTS[tile-16],heights,true,watered,pipe_depth,pipe_ends)
	elif tile in [31,32]:
		routes(parts,5 if tile==31 else 10,heights,false,false,-12,subway_ends,true,compact)
		routes(parts,10 if tile==31 else 5,heights,true,watered,pipe_depth,pipe_ends)
	elif tile==35:
		routes(parts,15,heights,false,false,-12,subway_ends,false)
		var top := G.surface_height(Vector2.ZERO,heights)
		G.box(parts,"silo",Vector3(-.16,-.16,-12),Vector3(.16,.16,top))
		for step in 3:
			G.box(parts,"rail",Vector3(-.165,-.165,top-step*4-1),Vector3(.165,.165,top-step*4-.5))
	elif tile==34:
		G.box(parts,"silo",Vector3(-.24,-.24,-24),Vector3(.24,.24,-1))
	elif sprite==352 or sprite in range(62,126):
		routes(parts,10 if sprite==352 else 5,heights,false,false,-24,PackedFloat32Array(),false)
	var baseline := BASELINE
	for part: Dictionary in parts:
		for vertex: Vector3 in part.vertices:
			baseline=maxi(baseline,ceili(G.project(vertex).y)+1)
	return {"parts":parts,"ports":0,"footprint":1,"baseline":baseline}


static func routes(parts: Array, mask: int, heights: PackedFloat32Array, pipe: bool, watered: bool, depth := -12.0, ends := PackedFloat32Array(), subway_style := true, compact := false) -> void:
	var first_part := parts.size()
	var center := Vector3(0,0,G.surface_height(Vector2.ZERO,heights)+depth)
	# Keep the compact glyph and pipes unchanged. Elbows expose a different cut side.
	var detailed := subway_style and not compact and not pipe
	var elbow := detailed and mask in [3,6,9,12]
	var green_elbow := elbow and mask in [6,9]
	var openings := {}
	if not pipe and detailed and mask not in [5,10]:
		for k in 4:
			if mask&(1<<k):
				var p: Vector2=G.STEPS[k]
				var end := Vector3(p.x,p.y,ends[k] if ends.size()==4 else G.surface_height(p,heights)+depth)
				openings[k]=tunnel_planes(center+Vector3(0,0,LINING_LIFT),end+Vector3(0,0,LINING_LIFT),TUNNEL_INNER_RADIUS,1.0)
	for k in 4:
		if not mask&(1<<k):
			continue
		var p: Vector2=G.STEPS[k]
		var end := Vector3(p.x,p.y,ends[k] if ends.size()==4 else G.surface_height(p,heights)+depth)
		var across := Vector3(-p.y,p.x,0).normalized()
		if pipe:
			tube(parts,"wet_pipe" if watered else "dry_pipe",center,end,PIPE_RADIUS)
			tube(parts,"rim",end,end-(end-center)*.04,PIPE_COLLAR_RADIUS)
		else:
			# The original shows a green cylindrical shell and gray, hollow mouths.
			# Both skins remain outside the train envelope; no end disc blocks it.
			var width_scale := TUNNEL_WIDTH_SCALE if detailed else 1.0
			# Compensate half the cross-section's projected rise without moving its axis.
			var bank := .5 if detailed else 0.0
			var cuts := []
			for other: int in openings:
				if other!=k:
					cuts.append(openings[other])
			tube(parts,"tube",center,end,TUNNEL_RADIUS,SHELL_FACETS if subway_style else [],width_scale,bank,cuts)
			var lift := Vector3(0,0,LINING_LIFT if detailed else 0.0)
			var inner_facets := SHELL_FACETS if green_elbow else (DARK_LINING_FACETS if elbow else LINING_FACETS)
			tube(parts,"lining",center+lift,end+lift,TUNNEL_INNER_RADIUS,inner_facets if subway_style else [],1.0,bank,cuts)
			var axis := Vector2(end.x-center.x,end.y-center.y).normalized()
			var normal := Vector3(-axis.y/32,axis.x/32,0)
			normal.z=G.project(normal).y*bank
			for segment in 8:
				var angle := segment*PI/4
				var a := normal*cos(angle)*TUNNEL_RADIUS*width_scale+Vector3(0,0,sin(angle)*TUNNEL_RADIUS)
				var b := normal*cos(angle+PI/4)*TUNNEL_RADIUS*width_scale+Vector3(0,0,sin(angle+PI/4)*TUNNEL_RADIUS)
				var height := TUNNEL_INNER_RADIUS
				var inner_a := normal*cos(angle)*TUNNEL_INNER_RADIUS+Vector3(0,0,sin(angle)*height)+lift
				var inner_b := normal*cos(angle+PI/4)*TUNNEL_INNER_RADIUS+Vector3(0,0,sin(angle+PI/4)*height)+lift
				if detailed:
					var rim_a := a*(7.5/TUNNEL_RADIUS)
					var rim_b := b*(7.5/TUNNEL_RADIUS)
					var rim_role: String=SHELL_FACETS[segment] if green_elbow else ("arch" if elbow else "tunnel_dark")
					G.face(parts,rim_role,PackedVector3Array([end+a,end+b,end+rim_b,end+rim_a]))
					var roles := MOUTH_ALONG_Y if absf(p.y)>.1 else MOUTH_ALONG_X
					var role: String=SHELL_FACETS[segment] if green_elbow else ("tunnel_dark" if elbow else roles[segment])
					G.face(parts,role,PackedVector3Array([end+rim_a,end+rim_b,end+inner_b,end+inner_a]))
				else:
					var inner := TUNNEL_INNER_RADIUS/TUNNEL_RADIUS
					var role: String=COMPACT_MOUTH_FACETS[segment] if subway_style else "cut"
					G.face(parts,role,PackedVector3Array([end+a,end+b,end+b*inner,end+a*inner]))
			for sign_value in [-1,1]:
				G.beam(parts,"subway_rail" if subway_style else "rail",center+across*.09*sign_value,end+across*.09*sign_value,0.7)
			for t in [.15,.45,.75]:
				var at := center.lerp(end,t)-Vector3(0,0,.6)
				G.beam(parts,"sleeper",at-across*.14,at+across*.14,1)
	if elbow and not green_elbow:
		cutaway_elbow(parts,first_part,mask)


# Match the original open section without moving tracks or adding an end cap.
static func cutaway_elbow(parts: Array, first_part: int, mask: int) -> void:
	var sign_value := 1.0 if mask==3 else -1.0
	var plane := Plane(Vector3(-sign_value,sign_value,0),0)
	var visible: Array = []
	for index in range(first_part,parts.size()):
		var part: Dictionary=parts[index]
		if part.role in ["subway_rail","sleeper"]:
			visible.append(part)
		else:
			var polygon := clip_polygon(part.vertices,plane,true)
			if polygon.size()>=3:
				G.face(visible,part.role,polygon)
	parts.resize(first_part)
	parts.append_array(visible)


static func tube(parts: Array, role: String, a: Vector3, b: Vector3, radius: float, facets: Array = [], width_scale := 1.0, bank := 0.0, cuts: Array = []) -> void:
	var direction := Vector2(b.x-a.x,b.y-a.y).normalized()
	var across := Vector3(-direction.y/32,direction.x/32,0)*width_scale
	across.z=G.project(across).y*bank
	for k in 8:
		var angle := k*TAU/8
		var next := angle+TAU/8
		var p := across*cos(angle)*radius+Vector3(0,0,sin(angle)*radius)
		var q := across*cos(next)*radius+Vector3(0,0,sin(next)*radius)
		carved_face(parts,facets[k] if not facets.is_empty() else role,PackedVector3Array([a+p,b+p,b+q,a+q]),cuts)


static func carved_face(parts: Array, role: String, vertices: PackedVector3Array, cuts: Array) -> void:
	if cuts.is_empty():
		G.face(parts,role,vertices)
		return
	var polygons: Array[PackedVector3Array]=[vertices]
	for volume: Array in cuts:
		var outside: Array[PackedVector3Array]=[]
		for polygon: PackedVector3Array in polygons:
			outside.append_array(outside_tunnel(polygon,volume))
		polygons=outside
	for polygon: PackedVector3Array in polygons:
		G.face(parts,role,polygon)


# Convex half-spaces follow the same octagonal section as tube(), including its grade.
static func tunnel_planes(a: Vector3, b: Vector3, radius: float, width_scale: float) -> Array:
	var direction := Vector2(b.x-a.x,b.y-a.y).normalized()
	var along := Vector3(direction.x,direction.y,0)
	var across := Vector3(-direction.y,direction.x,0)*32.0/width_scale
	var slope := (b.z-a.z)/Vector2(b.x-a.x,b.y-a.y).length()
	var result := [Plane(-along,-along.dot(a)),Plane(along,along.dot(b))]
	for k in 8:
		var angle := (k+.5)*TAU/8
		var bank := 4.0*(-direction.y+direction.x)
		var up := Vector3(direction.y*bank,-direction.x*bank,1)
		var normal := across*cos(angle)+(up-along*slope)*sin(angle)
		result.append(Plane(normal,normal.dot(a)+radius*cos(PI/8)))
	return result


static func outside_tunnel(polygon: PackedVector3Array, planes: Array) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array]=[]
	var remaining := polygon
	for plane: Plane in planes:
		var outside := clip_polygon(remaining,plane,false)
		if outside.size()>=3:
			result.append(outside)
		remaining=clip_polygon(remaining,plane,true)
		if remaining.size()<3:
			break
	return result


static func clip_polygon(polygon: PackedVector3Array, plane: Plane, inside: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	if polygon.is_empty():
		return result
	var previous := polygon[-1]
	var previous_distance := plane.distance_to(previous)
	var previous_kept := previous_distance<=.00001 if inside else previous_distance>.00001
	for point: Vector3 in polygon:
		var distance := plane.distance_to(point)
		var kept := distance<=.00001 if inside else distance>.00001
		if kept!=previous_kept:
			result.append(previous.lerp(point,previous_distance/(previous_distance-distance)))
		if kept:
			result.append(point)
		previous=point
		previous_distance=distance
		previous_kept=kept
	return result
