class_name VehicleModels
extends RefCounted
## Shared rigid vehicle bodies, rasterized at the same pixel grid as the city.
@warning_ignore_start("integer_division")

enum Kind { CAR, TRUCK, BUS, ENGINE, COACH, BULLDOZER }
const BODY_COLORS := [Color("972713"), Color("c7c7b7"), Color("b79737"),
	Color("376747"), Color("375777"), Color("777777")]
const LIMIT := 2048
var frames: Dictionary = {}
var swatches: Dictionary = {}
var palette_source: Sc2Palette
var meshes: Dictionary = {}


func frame(kind: int, variant: int, forward: Vector2, rise: float, palette: Sc2Palette, divisor := 1) -> Dictionary:
	if palette != palette_source:
		palette_source = palette
		frames.clear()
		swatches.clear()
	# Quarter terrain and the existing ramp geometry have exact discrete grades.
	rise = snappedf(rise,.5)
	var shape := Kind.ENGINE if kind == Kind.COACH else kind
	var geometry_key := var_to_bytes([shape,forward,rise]).hex_encode()
	var key := var_to_bytes([kind,geometry_key,variant % BODY_COLORS.size(),divisor]).hex_encode()
	if frames.has(key):
		return frames[key]
	if frames.size() >= LIMIT:
		frames.clear()
		meshes.clear()
	var color_key := Vector2i(kind,variant % BODY_COLORS.size())
	if not swatches.has(color_key):
		swatches[color_key] = _materials(kind,variant,palette)
	if not meshes.has(geometry_key):
		meshes[geometry_key] = geometry(shape,forward,rise)
	var recipe: Dictionary = meshes[geometry_key].duplicate()
	recipe.materials = swatches[color_key]
	var source := Image.create(32,32,false,Image.FORMAT_RGBA8)
	var raster := NetworkModelRaster.render(0,source,palette,2,recipe)
	var entry: Sc2SpriteArchive.SpriteEntry = raster.entry
	var full: Image = raster.image
	var rect := full.get_used_rect().grow(1).intersection(Rect2i(Vector2i.ZERO,full.get_size()))
	# Align the crop to the native artwork grid before nearest-pixel reduction.
	var first := Vector2i(floori(float(rect.position.x)/divisor),floori(float(rect.position.y)/divisor))*divisor
	var end := Vector2i(ceili(float(rect.end.x)/divisor),ceili(float(rect.end.y)/divisor))*divisor
	rect = Rect2i(first,end-first)
	var indexed: Image = entry.create_image(Sc2Palette.index_encoding()).image
	var lamps := Image.create(full.get_width(),full.get_height(),false,Image.FORMAT_RGBA8)
	for y in full.get_height():
		for x in full.get_width():
			var role: int = raster.roles[y*full.get_width()+x]
			if role >= 3:
				lamps.set_pixel(x,y,[Color("ffe3a0"),Color("ff3426"),Color("709fff")][role-3])
	var images: Array[Image] = []
	for image: Image in [full,indexed,lamps]:
		var cropped := Image.create(rect.size.x,rect.size.y,false,Image.FORMAT_RGBA8)
		cropped.blit_rect(image,rect,Vector2i.ZERO)
		if divisor > 1:
			cropped.resize(rect.size.x/divisor,rect.size.y/divisor,Image.INTERPOLATE_NEAREST)
			cropped.resize(rect.size.x,rect.size.y,Image.INTERPOLATE_NEAREST)
		images.append(cropped)
	images[0].set_meta("vehicle_model_lamps",images[2])
	var result := {"image":images[0],"indexed":images[1],"lamps":images[2],
		"anchor":Vector2(16,entry.height-9)-Vector2(rect.position),"recipe":recipe}
	frames[key] = result
	return result


static func _materials(kind: int, variant: int, palette: Sc2Palette) -> Dictionary:
	var body: Color = BODY_COLORS[variant % BODY_COLORS.size()]
	if kind in [Kind.ENGINE,Kind.COACH]:
		body = Color("bfbfbf")
	elif kind == Kind.BULLDOZER:
		body = Color("978313")
	var colors := {"body":body,"roof":body.lightened(.12),"glass":Color("203747"),
		"wheel":Color("101010"),"trim":Color("b7b7a7"),"headlamp":Color("eee7bf"),
		"taillamp":Color("b71707"),"beacon":Color("3757b7"),
		"window_frame":Color("202020"),"metal":Color("777777"),"cargo":Color("bfbfbf"),
		"cargo_seam":Color("777777"),"track":Color("000000"),"blade":Color("3b3b3b")}
	if kind in [Kind.ENGINE,Kind.COACH]:
		colors.roof = Color("7f7f7f")
		colors.glass = Color("575757")
		colors.wheel = Color("470000")
		colors.trim = Color("bfbfbf")
	colors.train_front = Color("0000df")
	var result := {}
	for role: String in colors:
		var c: Color = colors[role]
		result[role] = PackedInt32Array([NetworkModelRaster.nearest(palette,c),
			NetworkModelRaster.nearest(palette,c.lightened(.18)),NetworkModelRaster.nearest(palette,c.darkened(.25))])
	result.deck = result.body
	if kind == Kind.BULLDOZER:
		# The original machine uses an olive yellow, black tracks and dark steel.
		var original_shades := {"body":["978313","bfb32b","6f5700"],
			"blade":["3b3b3b","3b3b3b","2f2f2f"],"track":["000000","2f2f2f","000000"]}
		for role: String in original_shades:
			var shades: Array = original_shades[role]
			result[role] = PackedInt32Array([NetworkModelRaster.nearest(palette,Color(shades[0])),
				NetworkModelRaster.nearest(palette,Color(shades[1])),NetworkModelRaster.nearest(palette,Color(shades[2]))])
	return result


static func geometry(kind: int, forward: Vector2, rise: float) -> Dictionary:
	var parts: Array = []
	var length: float = [.46,.62,.74,.94,.94,.78][kind]
	var half := length*.5
	var width := .105 if kind == Kind.CAR else (.25 if kind == Kind.BULLDOZER else .13)
	var height := 2.0 if kind == Kind.CAR else (4.2 if kind == Kind.BULLDOZER else (3.7 if kind >= Kind.ENGINE else 3.0))
	if kind != Kind.BULLDOZER:
		NetworkModelGeometry.box(parts,"wheel",Vector3(-half*.9,-width*.65,.25),Vector3(half*.9,width*.65,.9))
		NetworkModelGeometry.box(parts,"body",Vector3(-half,-width,.65),Vector3(half,width,height))
	if kind in [Kind.ENGINE,Kind.COACH]:
		roof(parts,Vector3(-half,-width,height),Vector3(half,width,height+1.0))
		for window in 3:
			var x := -half+.10+window*(length-.16)/3.0
			window_band(parts,x,x+.10,width,1.95,3.35)
		NetworkModelGeometry.box(parts,"train_front",Vector3(half,-width,1.1),Vector3(half+.005,width,3.5))
		NetworkModelGeometry.box(parts,"glass",Vector3(half+.005,-width*.65,2.65),Vector3(half+.009,width*.65,3.25))
		for side in [-1,1]:
			NetworkModelGeometry.box(parts,"metal",Vector3(.28,side*width-.008,.95),Vector3(.292,side*width+.008,3.6))
		for end in [-1,1]:
			NetworkModelGeometry.box(parts,"wheel",Vector3(end*half-.04,-.035,.6),Vector3(end*half+.04,.035,1.2))
	elif kind == Kind.TRUCK:
		NetworkModelGeometry.box(parts,"cargo",Vector3(-half,-width,1.3),Vector3(.07,width,4.1))
		window_band(parts,.11,half-.03,width,2,3.25)
		roof(parts,Vector3(.09,-width,3.25),Vector3(half-.015,width,3.6))
		for seam in [-.08,0,.08]:
			NetworkModelGeometry.box(parts,"cargo_seam",Vector3(-half-.004,seam-.006,1.5),Vector3(-half+.001,seam+.006,3.95))
	elif kind == Kind.BUS:
		for window in 5:
			var x := -half+.04+window*(length-.08)/5.0
			window_band(parts,x,x+.10,width,2,3.7)
		roof(parts,Vector3(-half,-width,3.8),Vector3(half,width,4.1))
		NetworkModelGeometry.box(parts,"metal",Vector3(half*.63,-width-.006,.95),Vector3(half*.63+.015,width+.006,3.7))
		NetworkModelGeometry.box(parts,"metal",Vector3(-.10,-.055,4.1),Vector3(.04,.055,4.23))
	elif kind == Kind.BULLDOZER:
		bulldozer(parts)
	else:
		var cab := half*.65
		window_band(parts,-cab,cab,width,height-.65,height+.8)
		roof(parts,Vector3(-cab,-width,height+.8),Vector3(cab,width,height+1.05))
		NetworkModelGeometry.box(parts,"body",Vector3(-.014,-width-.008,height-.65),Vector3(.014,width+.008,height+.8))
		NetworkModelGeometry.box(parts,"roof",Vector3(cab+.02,-width*.7,height),Vector3(half-.01,width*.7,height+.08))
	if kind != Kind.BULLDOZER:
		for axle in [-half*.65,half*.65]:
			for side in [-1,1]:
				NetworkModelGeometry.box(parts,"wheel",Vector3(axle-.045,side*width-.025,0),Vector3(axle+.045,side*width+.025,1.1))
				if kind in [Kind.CAR,Kind.TRUCK,Kind.BUS]:
					NetworkModelGeometry.box(parts,"metal",Vector3(axle-.02,side*width-.028,.4),Vector3(axle+.02,side*width+.028,.75))
	if kind != Kind.BULLDOZER:
		for end in [-1,1]:
			NetworkModelGeometry.box(parts,"trim",Vector3(end*half-.012,-width,.65),Vector3(end*half+.012,width,.95))
		for side in [-1,1]:
			NetworkModelGeometry.box(parts,"headlamp",Vector3(half-.01,side*width*.65-.023,1),Vector3(half+.01,side*width*.65+.023,1.65))
			NetworkModelGeometry.box(parts,"taillamp",Vector3(-half-.01,side*width*.65-.023,1),Vector3(-half+.01,side*width*.65+.023,1.6))
	# A rigid pitch rotation moves the roof, wheel axles and lamp meshes together.
	# Horizontal coordinates are tile units, vertical coordinates native pixels.
	var heading := forward.normalized()
	var angle := atan2(rise,32.0)
	var along := Vector3(heading.x*cos(angle),heading.y*cos(angle),32.0*sin(angle))
	var across := Vector3(-heading.y,heading.x,0)
	var up := Vector3(-heading.x*sin(angle)/32.0,-heading.y*sin(angle)/32.0,cos(angle))
	for part: Dictionary in parts:
		for i in part.vertices.size():
			var p: Vector3 = part.vertices[i]
			part.vertices[i] = along*p.x+across*p.y+up*p.z
	return {"parts":parts,"ports":0,"footprint":1}


static func bulldozer(parts: Array) -> void:
	NetworkModelGeometry.box(parts,"body",Vector3(-.32,-.18,1.4),Vector3(.33,.18,3.6))
	NetworkModelGeometry.box(parts,"body",Vector3(-.01,-.17,3.6),Vector3(.33,.17,5.0))
	# Open operator station: upright back, dark seat and exposed controls.
	for side in [-1,1]:
		NetworkModelGeometry.box(parts,"body",Vector3(-.31,side*.13-.025,3.5),Vector3(-.25,side*.13+.025,8.7))
	NetworkModelGeometry.box(parts,"body",Vector3(-.31,-.15,7.5),Vector3(-.25,.15,8.7))
	NetworkModelGeometry.box(parts,"track",Vector3(-.25,-.10,4.3),Vector3(-.20,.10,6.3))
	NetworkModelGeometry.box(parts,"track",Vector3(-.24,-.12,3.8),Vector3(-.04,.12,4.6))
	NetworkModelGeometry.beam(parts,"track",Vector3(-.04,-.06,3.8),Vector3(.01,-.06,6.0),.7)
	NetworkModelGeometry.box(parts,"track",Vector3(.10,-.15,4.8),Vector3(.14,-.11,8.8))
	for side in [-1,1]:
		NetworkModelGeometry.box(parts,"body",Vector3(-.28,side*.17-.035,3.6),Vector3(-.04,side*.17+.035,5.8))
		NetworkModelGeometry.box(parts,"track",Vector3(-.39,side*.23-.07,0),Vector3(.39,side*.23+.07,1.9))
		for roller in 3:
			var x := -.28+roller*.28
			NetworkModelGeometry.box(parts,"metal",Vector3(x-.045,side*.23-.073,.3),Vector3(x+.045,side*.23+.073,1.1))
		NetworkModelGeometry.beam(parts,"blade",Vector3(.0,side*.22,1.2),Vector3(.47,side*.28,2.1),.9)
	# Tall, concave shield with a bright cutting edge, rather than a low bumper.
	var profile := [Vector2(.49,.2),Vector2(.45,2.0),Vector2(.44,5.0),Vector2(.48,7.0)]
	for i in 3:
		NetworkModelGeometry.face(parts,"blade",PackedVector3Array([
			Vector3(profile[i].x,-.36,profile[i].y),Vector3(profile[i].x,.36,profile[i].y),
			Vector3(profile[i+1].x,.36,profile[i+1].y),Vector3(profile[i+1].x,-.36,profile[i+1].y)]))
	NetworkModelGeometry.box(parts,"metal",Vector3(.48,-.365,.1),Vector3(.51,.365,.65))


static func window_band(parts: Array, first: float, last: float, width: float, low: float, high: float) -> void:
	NetworkModelGeometry.box(parts,"window_frame",Vector3(first,-width-.003,low),Vector3(last,width+.003,high))
	NetworkModelGeometry.box(parts,"glass",Vector3(first+.012,-width-.006,low+.12),Vector3(last-.012,width+.006,high-.12))


static func roof(parts: Array, low: Vector3, high: Vector3) -> void:
	var profile := [Vector2(low.y,low.z),Vector2(lerpf(low.y,high.y,.18),high.z),
		Vector2(lerpf(low.y,high.y,.82),high.z),Vector2(high.y,low.z)]
	for i in 3:
		NetworkModelGeometry.face(parts,"roof",PackedVector3Array([
			Vector3(low.x,profile[i].x,profile[i].y),Vector3(high.x,profile[i].x,profile[i].y),
			Vector3(high.x,profile[i+1].x,profile[i+1].y),Vector3(low.x,profile[i+1].x,profile[i+1].y)]))
	for x in [low.x,high.x]:
		var cap := PackedVector3Array()
		for p: Vector2 in profile:
			cap.append(Vector3(x,p.x,p.y))
		NetworkModelGeometry.face(parts,"roof",cap)


static func height(city: CityState, world: Vector2) -> float:
	var tile := Vector2i((world+Vector2(.5,.5)).floor())
	if city.index_of(tile.x,tile.y) < 0:
		return 0.0
	var local := world-Vector2(tile)
	var n := CityLifePaths.edge_height(city,tile,0)
	var e := CityLifePaths.edge_height(city,tile,1)
	var s := CityLifePaths.edge_height(city,tile,2)
	var w := CityLifePaths.edge_height(city,tile,3)
	return (n+e+s+w)*.25+(e-w)*local.x+(s-n)*local.y


static func rise_at(city: CityState, world: Vector2, forward: Vector2, wheelbase := .34) -> float:
	return (height(city,world+forward*wheelbase)-height(city,world-forward*wheelbase))*12.0/(wheelbase*2)


static func contact(city: CityState, world: Vector2) -> Vector2:
	return Vector2(32+(city.map_size+world.x-world.y)*16+16,
		512+(world.x+world.y)*8+8-height(city,world)*12)
