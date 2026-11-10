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
		body = Color("b79737")
	var colors := {"body":body,"roof":body.lightened(.12),"glass":Color("203747"),
		"wheel":Color("101010"),"trim":Color("b7b7a7"),"headlamp":Color("eee7bf"),
		"taillamp":Color("b71707"),"beacon":Color("3757b7")}
	if kind in [Kind.ENGINE,Kind.COACH]:
		colors.roof = Color("7f7f7f")
		colors.glass = Color("575757")
		colors.wheel = Color("470000")
	colors.train_front = Color("0000df")
	var result := {}
	for role: String in colors:
		var c: Color = colors[role]
		result[role] = PackedInt32Array([NetworkModelRaster.nearest(palette,c),
			NetworkModelRaster.nearest(palette,c.lightened(.18)),NetworkModelRaster.nearest(palette,c.darkened(.25))])
	result.deck = result.body
	return result


static func geometry(kind: int, forward: Vector2, rise: float) -> Dictionary:
	var parts: Array = []
	var length: float = [.46,.62,.74,.94,.94,.46][kind]
	var half := length*.5
	var width := .105 if kind == Kind.CAR else .13
	var height := 2.0 if kind == Kind.CAR else (3.7 if kind >= Kind.ENGINE else 3.0)
	NetworkModelGeometry.box(parts,"body",Vector3(-half,-width,.65),Vector3(half,width,height))
	if kind in [Kind.ENGINE,Kind.COACH]:
		NetworkModelGeometry.box(parts,"roof",Vector3(-half,-width,height),Vector3(half,width,height+1.0))
		for window in 3:
			var x := -half+.10+window*(length-.16)/3.0
			NetworkModelGeometry.box(parts,"glass",Vector3(x,-width-.004,2),Vector3(x+.09,width+.004,3.3))
		NetworkModelGeometry.box(parts,"train_front",Vector3(half,-width,1.1),Vector3(half+.005,width,3.5))
	elif kind == Kind.TRUCK:
		NetworkModelGeometry.box(parts,"roof",Vector3(-half,-width,1.3),Vector3(.07,width,4.1))
		NetworkModelGeometry.box(parts,"glass",Vector3(.11,-width-.003,2),Vector3(half-.04,width+.003,3.2))
	elif kind == Kind.BULLDOZER:
		NetworkModelGeometry.box(parts,"glass",Vector3(-.05,-.09,height),Vector3(.1,.09,height+1.2))
		NetworkModelGeometry.box(parts,"trim",Vector3(half,-.2,.3),Vector3(half+.04,.2,1.6))
	else:
		var cab := half*.65
		NetworkModelGeometry.box(parts,"glass",Vector3(-cab,-width-.003,height-.65),Vector3(cab,width+.003,height+.8))
		NetworkModelGeometry.box(parts,"roof",Vector3(-cab,-width,height+.8),Vector3(cab,width,height+1.05))
	for axle in [-half*.65,half*.65]:
		for side in [-1,1]:
			NetworkModelGeometry.box(parts,"wheel",Vector3(axle-.045,side*width-.025,0),Vector3(axle+.045,side*width+.025,1.1))
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
