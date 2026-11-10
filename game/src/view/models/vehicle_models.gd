class_name VehicleModels
extends RefCounted
## Shared rigid vehicle bodies, rasterized at the same pixel grid as the city.
@warning_ignore_start("integer_division")

enum Kind { CAR, TRUCK, BUS, ENGINE, COACH, BULLDOZER, AIRPLANE, HELICOPTER, SHIP, SAILBOAT }
const BODY_COLORS := [Color("0000b3"), Color("bfbfbf"), Color("df0000"),
	Color("bfb300"), Color("007700"), Color("7f7f7f")]
const AIRCRAFT_SHADES := {
	"air_top":["f3f3f3","f3f3f3","c7c7c7"],
	"air_side":["c7c7c7","dfdfdf","8f8f8f"],
	"air_lower":["4b4b4b","676767","2f2f2f"],
	"air_wing":["c7c7c7","dfdfdf","9f9f9f"],
	"air_wing_root":["ababab","c7c7c7","8f8f8f"],
	"air_edge":["575757","676767","2f2f2f"],
	"air_leading":["f3f3f3","f3f3f3","bfbfbf"],
	"air_engine":["9f9f9f","bfbfbf","575757"],
	"air_intake":["2f2f2f","2f2f2f","2f2f2f"],
	"air_tail_base":["0b53f3","1b77d3","0b53f3"],
	"air_tail_tip":["0793d7","13b7f3","1b77d3"]}
const LIMIT := 2048
var frames: Dictionary = {}
var swatches: Dictionary = {}
var palette_source: Sc2Palette
var meshes: Dictionary = {}


func frame(kind: int, variant: int, forward: Vector2, rise: float, palette: Sc2Palette, divisor := 1, shadow := false) -> Dictionary:
	if palette != palette_source:
		palette_source = palette
		frames.clear()
		swatches.clear()
	# Quarter terrain and the existing ramp geometry have exact discrete grades.
	rise = snappedf(rise,.5)
	var shape := Kind.ENGINE if kind == Kind.COACH else kind
	var compact := kind==Kind.AIRPLANE and divisor>1
	var geometry_key := var_to_bytes([shape,forward,rise,shadow,compact]).hex_encode()
	var key := var_to_bytes([kind,geometry_key,variant % BODY_COLORS.size(),divisor]).hex_encode()
	if frames.has(key):
		return frames[key]
	if frames.size() >= LIMIT:
		frames.clear()
		meshes.clear()
	var color_key := Vector3i(kind,variant % BODY_COLORS.size(),int(compact))
	if not swatches.has(color_key):
		swatches[color_key] = _materials(kind,variant,palette,compact)
	if not meshes.has(geometry_key):
		meshes[geometry_key] = geometry(shape,forward,rise,compact)
		if shadow:
			for part: Dictionary in meshes[geometry_key].parts:
				for i in part.vertices.size():
					part.vertices[i].z=0
	var recipe: Dictionary = meshes[geometry_key].duplicate()
	recipe.materials = swatches[color_key]
	# Long ships and steep subway poses extend below the contact point.
	# Reserve their full projected extent before cropping the native raster.
	var baseline := 9
	for part: Dictionary in recipe.parts:
		for vertex: Vector3 in part.vertices:
			baseline=maxi(baseline,ceili(NetworkModelGeometry.project(vertex).y)+1)
	recipe.baseline=baseline
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
	var lamps := NetworkModelRaster.emission(raster)
	var images: Array[Image] = []
	for image: Image in [full,indexed,lamps]:
		var cropped := Image.create(rect.size.x,rect.size.y,false,Image.FORMAT_RGBA8)
		cropped.blit_rect(image,rect,Vector2i.ZERO)
		if divisor > 1:
			if kind>=Kind.AIRPLANE:
				cropped=reduce_coverage(cropped,divisor)
			else:
				cropped.resize(rect.size.x/divisor,rect.size.y/divisor,Image.INTERPOLATE_NEAREST)
			cropped.resize(rect.size.x,rect.size.y,Image.INTERPOLATE_NEAREST)
		images.append(cropped)
	images[0].set_meta("vehicle_model_lamps",images[2])
	var result := {"image":images[0],"indexed":images[1],"lamps":images[2],
		"anchor":Vector2(float(recipe.get("origin_x",16)),entry.height-baseline)-Vector2(rect.position),"recipe":recipe}
	if kind in [Kind.SHIP,Kind.SAILBOAT] and not shadow:
		result.merge(floating_images(raster,indexed,lamps,rect,divisor))
	frames[key] = result
	return result


static func floating_images(raster: Dictionary, indexed: Image, lamps: Image, rect: Rect2i, divisor: int) -> Dictionary:
	var body := Image.create(rect.size.x,rect.size.y,false,Image.FORMAT_RGBA8)
	var clean := Image.create(rect.size.x,rect.size.y,false,Image.FORMAT_RGBA8)
	var reflected := Image.create(rect.size.x,rect.size.y*2,false,Image.FORMAT_RGBA8)
	var light := Image.create(rect.size.x,rect.size.y*2,false,Image.FORMAT_RGBA8)
	var reflected_depth := PackedFloat32Array()
	reflected_depth.resize(reflected.get_width()*reflected.get_height())
	reflected_depth.fill(-INF)
	for y in indexed.get_height():
		for x in indexed.get_width():
			var pixel := indexed.get_pixel(x,y)
			if pixel.a==0 or not rect.has_point(Vector2i(x,y)):
				continue
			var role: int=raster.roles[y*indexed.get_width()+x]
			var local := Vector2i(x,y)-rect.position
			if role==6:
				continue
			if role==7:
				clean.set_pixelv(local,Color(154.0/255,0,0,.4))
				continue
			body.set_pixelv(local,pixel)
			clean.set_pixelv(local,pixel)
			var z: float=raster.signed_height[y*indexed.get_width()+x]
			if z<0:
				continue
			var target := Vector2i(local.x,roundi(local.y+2*z))
			if target.y>=reflected.get_height():
				continue
			# Mirroring height reverses the vertical visit order. Resolve each
			# reflected sample by its spatial depth instead of source-image order,
			# or a later hull pixel can erase an already visible navigation light.
			var depth: float=raster.depth[y*indexed.get_width()+x]-z*.25
			var at := target.y*reflected.get_width()+target.x
			if depth<reflected_depth[at]:
				continue
			reflected_depth[at]=depth
			pixel.a*=maxf(0,1-z/255.0)
			reflected.set_pixelv(target,pixel)
			light.set_pixelv(target,lamps.get_pixel(x,y))
	if divisor>1:
		for image: Image in [body,clean,reflected,light]:
			var size := image.get_size()
			var reduced := reduce_coverage(image,divisor)
			reduced.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
			image.copy_from(reduced)
	return {"floating_source":body,"water_indexed":clean,"reflection":reflected,"reflection_lamps":light}


static func reduce_coverage(source: Image, divisor: int) -> Image:
	var result := Image.create(source.get_width()/divisor,source.get_height()/divisor,false,Image.FORMAT_RGBA8)
	for y in result.get_height():
		for x in result.get_width():
			var nearest := INF
			for dy in divisor:
				for dx in divisor:
					var color := source.get_pixel(x*divisor+dx,y*divisor+dy)
					var distance := Vector2(dx+.5-divisor*.5,dy+.5-divisor*.5).length_squared()
					if color.a>.5 and distance<nearest:
						result.set_pixel(x,y,color)
						nearest=distance
	return result


static func _materials(kind: int, variant: int, palette: Sc2Palette, compact: bool) -> Dictionary:
	var body: Color = BODY_COLORS[variant % BODY_COLORS.size()]
	if kind in [Kind.ENGINE,Kind.COACH]:
		body = Color("bfbfbf")
	elif kind == Kind.BULLDOZER:
		body = Color("978313")
	var colors := {"body":body,"roof":body.lightened(.12),"glass":Color("575757"),
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
	colors.white = Color("dfdfdf")
	colors.blue = Color("13b7f3")
	colors.red = Color("df0000")
	colors.hull = Color("000000")
	colors.rotor = Color("0000df")
	colors.rotor_blur = Color("2720ff")
	colors.nav_white=Color("dfdfdf")
	colors.nav_red=Color("dfdfdf")
	colors.cargo_red=Color("df0000")
	colors.cargo_blue=Color("0000b3")
	colors.cargo_yellow=Color("bfb300")
	colors.cargo_white=Color("dfdfdf")
	if kind==Kind.HELICOPTER:
		colors.glass=Color("8f8f8f")
	var result := {}
	for role: String in colors:
		var c: Color = colors[role]
		result[role] = PackedInt32Array([NetworkModelRaster.nearest(palette,c),
			NetworkModelRaster.nearest(palette,c.lightened(.18)),NetworkModelRaster.nearest(palette,c.darkened(.25))])
	result.deck = result.body
	if kind==Kind.AIRPLANE and not compact:
		for role: String in AIRCRAFT_SHADES:
			var shades: Array=AIRCRAFT_SHADES[role]
			result[role]=PackedInt32Array([NetworkModelRaster.nearest(palette,Color(shades[0])),
				NetworkModelRaster.nearest(palette,Color(shades[1])),NetworkModelRaster.nearest(palette,Color(shades[2]))])
	if kind == Kind.BULLDOZER:
		# The original machine uses an olive yellow, black tracks and dark steel.
		var original_shades := {"body":["978313","bfb32b","6f5700"],
			"blade":["3b3b3b","3b3b3b","2f2f2f"],"track":["000000","2f2f2f","000000"]}
		for role: String in original_shades:
			var shades: Array = original_shades[role]
			result[role] = PackedInt32Array([NetworkModelRaster.nearest(palette,Color(shades[0])),
				NetworkModelRaster.nearest(palette,Color(shades[1])),NetworkModelRaster.nearest(palette,Color(shades[2]))])
	return result


static func geometry(kind: int, forward: Vector2, rise: float, compact := false) -> Dictionary:
	var parts: Array = []
	if kind>=Kind.AIRPLANE:
		return special_geometry(kind,forward,rise,compact)
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


static func special_geometry(kind: int, forward: Vector2, rise: float, compact: bool) -> Dictionary:
	var parts: Array = []
	var g = NetworkModelGeometry
	if kind==Kind.AIRPLANE:
		aircraft(parts,forward,compact)
	elif kind==Kind.HELICOPTER:
		g.box(parts,"red",Vector3(-.28,-.13,1),Vector3(.30,.13,3.7))
		g.box(parts,"glass",Vector3(.08,-.135,2.5),Vector3(.30,.135,3.75))
		g.box(parts,"red",Vector3(-.78,-.018,2.5),Vector3(-.25,.018,3.4))
		g.box(parts,"red",Vector3(-.78,-.018,3.4),Vector3(-.72,.018,6))
		for segment in 12:
			var a := segment*TAU/12.0
			var b := (segment+1)*TAU/12.0
			g.beam(parts,"metal",Vector3(-.80+cos(a)*.06,-.04,4.8+sin(a)*1.8),
				Vector3(-.80+cos(b)*.06,-.04,4.8+sin(b)*1.8),.55)
		g.box(parts,"metal",Vector3(-.06,-.012,3),Vector3(-.04,.012,6.6))
		for side in [-1,1]:
			g.beam(parts,"metal",Vector3(-.22,side*.17,0),Vector3(.25,side*.17,0),.7)
			g.beam(parts,"metal",Vector3(.08,side*.10,1.5),Vector3(.08,side*.17,0),.6)
		for part: Dictionary in parts:
			for i in part.vertices.size():
				part.vertices[i].x*=.88
				part.vertices[i].y*=.65
		# The original has a stable blue, dithered rotor sweep in every heading.
		# A horizontal spatial disk retains that silhouette and its palette cycle.
		for segment in 24:
			var a := segment*TAU/24.0
			var b := (segment+1)*TAU/24.0
			g.face(parts,"rotor_blur",PackedVector3Array([Vector3(-.044,0,6.6),
				Vector3(-.044+cos(a)*.50,sin(a)*.50,6.6),Vector3(-.044+cos(b)*.50,sin(b)*.50,6.6)]))
		g.box(parts,"rotor",Vector3(-.544,-.018,6.65),Vector3(.456,.018,6.72))
		g.box(parts,"rotor",Vector3(-.062,-.50,6.65),Vector3(-.026,.50,6.72))
		g.box(parts,"nav_white",Vector3(.23,-.065,1.1),Vector3(.29,.065,2.3))
		g.box(parts,"nav_red",Vector3(-.71,-.04,5.4),Vector3(-.63,.04,6.6))
	elif kind==Kind.SHIP:
		var outline := PackedVector3Array([Vector3(-1.32,-.24,0),Vector3(.90,-.29,0),Vector3(1.32,0,0),Vector3(.90,.29,0),Vector3(-1.32,.24,0)])
		g.slab(parts,"hull",outline,5)
		for i in outline.size():
			g.beam(parts,"red",outline[i]+Vector3(0,0,.8),outline[(i+1)%outline.size()]+Vector3(0,0,.8),1.3)
		g.box(parts,"white",Vector3(-1.17,-.19,.8),Vector3(-.72,.19,5.2))
		g.box(parts,"glass",Vector3(-1.175,-.195,3.8),Vector3(-.715,.195,4.5))
		g.box(parts,"white",Vector3(-1.19,-.20,5.2),Vector3(-.70,.20,5.8))
		g.box(parts,"red",Vector3(-1.26,-.09,4.0),Vector3(-1.13,.09,6.5))
		g.box(parts,"hull",Vector3(-1.26,-.09,6.5),Vector3(-1.13,.09,7.0))
		for window in 3:
			var x := -1.10+window*.13
			for side in [-1,1]:
				for level in [2.0,3.3]:
					g.box(parts,"glass",Vector3(x-.025,side*.195-.006,level),Vector3(x+.025,side*.195+.006,level+.6))
		g.beam(parts,"white",Vector3(-.84,0,4.8),Vector3(-.84,0,9),.7)
		for row in 6:
			for column in 3:
				var x := -.48+row*.23
				var y := (column-1)*.15
				var role: String=["cargo_white","cargo_red","cargo_yellow","cargo_blue"][(row+column)%4]
				g.box(parts,role,Vector3(x-.095,y-.06,.9),Vector3(x+.095,y+.06,2.25))
		g.beam(parts,"red",Vector3(-.65,0,.75),Vector3(1.1,0,.75),.7)
		for side in [-1,1]:
			g.box(parts,"nav_red" if side<0 else "nav_white",Vector3(-.77,side*.32-.035,4.6),Vector3(-.67,side*.32+.035,5.8))
	else:
		g.slab(parts,"white",PackedVector3Array([Vector3(-.33,-.08,0),Vector3(.25,-.09,0),Vector3(.38,0,0),Vector3(.25,.09,0),Vector3(-.33,.08,0)]),1)
		g.beam(parts,"metal",Vector3(0,0,0),Vector3(0,0,14),.6)
		g.face(parts,"red",PackedVector3Array([Vector3(0,0,13),Vector3(0,0,2),Vector3(.34,0,2)]))
		g.face(parts,"white",PackedVector3Array([Vector3(-.02,0,8),Vector3(-.25,0,1.5),Vector3(-.02,0,1.5)]))
	if kind in [Kind.SHIP,Kind.SAILBOAT]:
		var length := 1.32 if kind==Kind.SHIP else .38
		var width := .29 if kind==Kind.SHIP else .10
		for side in [-1,1]:
			g.face(parts,"wake",PackedVector3Array([Vector3(-length-.28,side*(width+.16),-.04),Vector3(length*.8,side*(width+.03),-.04),
				Vector3(length,side*width,-.04),Vector3(-length-.28,side*(width+.04),-.04)]))
			g.face(parts,"wake_foam",PackedVector3Array([Vector3(-length-.15,side*(width+.05),-.02),Vector3(length*.85,side*(width+.01),-.02),
				Vector3(length*.75,side*(width-.01),-.02),Vector3(-length-.15,side*(width+.015),-.02)]))
	var heading := forward.normalized()
	var angle := atan2(rise,32.0)
	var along := Vector3(heading.x*cos(angle),heading.y*cos(angle),32*sin(angle))
	var across := Vector3(-heading.y,heading.x,0)
	var up := Vector3(-heading.x*sin(angle)/32,-heading.y*sin(angle)/32,cos(angle))
	# The source artists lengthened the near-vertical screen poses. Preserve
	# their directional proportions before applying the rigid terrain pitch.
	var vertical_pose := maxf(0,2*heading.x*heading.y)
	# The rear axial sprite has a shorter projected tail than the nose-on sprite.
	var axial_detail := 0.0 if compact else vertical_pose
	var nose_scale := lerpf(1.0,.90,axial_detail)
	var tail_scale := lerpf(1.0,.88 if heading.x>0 else .60,axial_detail)
	for part: Dictionary in parts:
		for i in part.vertices.size():
			var p: Vector3=part.vertices[i]
			if kind==Kind.AIRPLANE:
				var length_scale := nose_scale if p.x>=0.0 else tail_scale
				p*=Vector3(.84*(1+.65*vertical_pose)*length_scale,.68,.8)
			elif kind==Kind.SHIP:
				p.x*=1+.25*vertical_pose
				p.y*=1.35
				if part.role not in ["wake","wake_foam"]:
					p.z+=5.0
			part.vertices[i]=along*p.x+across*p.y+up*p.z
	return {"parts":parts,"ports":0,"footprint":3,"origin_x":48}


static func kind_for_thing(type: int, state := 0) -> int:
	return {1:Kind.AIRPLANE,2:Kind.HELICOPTER,3:Kind.SHIP,4:Kind.BULLDOZER,
		9:Kind.SAILBOAT if state==0 else -1,10:Kind.ENGINE,11:Kind.COACH,
		12:Kind.ENGINE,13:Kind.COACH}.get(type,-1)


static func aircraft(parts: Array, forward: Vector2, compact: bool) -> void:
	var g = NetworkModelGeometry
	# SC2000 shortens the wing chord in its near-vertical screen poses.
	var direction := forward.normalized()
	# Use the compact profile of this same airframe in small native glyphs.
	# A wider fuselage and narrow paint panels alias into solid blocks there.
	var axial := 1.0 if compact else maxf(0,2*direction.x*direction.y)
	var detail := 0.0 if compact else axial
	var rear := detail if direction.x<0 else 0.0
	# The rear artwork projects the wider wing chord closer to the nose.
	var wing_shift := .44*rear
	var root := lerpf(.20,.10,axial)-.10*detail+wing_shift
	var sweep := lerpf(-.25,-.47,axial)+wing_shift
	var chord := lerpf(.55,.25,axial)+.27*detail+.07*rear
	var wing_span := 1.25*lerpf(1.0,.94,detail)
	var width := lerpf(.16,.10,axial)
	var radius := lerpf(1.9,1.3,axial)
	var rings: Array[Vector3]=[Vector3(-1.10,.025,.45),Vector3(-.94,width,radius),
		Vector3(.78,width,radius),Vector3(1.10,.008,.15)]
	for section in rings.size()-1:
		for segment in 8:
			var points := PackedVector3Array()
			for pair in [[section,segment],[section+1,segment],[section+1,segment+1],[section,segment+1]]:
				var ring: Vector3=rings[pair[0]]
				var angle: float=pair[1]*TAU/8.0
				points.append(Vector3(ring.x,cos(angle)*ring.y,2.3+sin(angle)*ring.z))
			var role := "air_top" if segment in [1,2] else ("air_side" if segment in [0,3] else "air_lower")
			g.face(parts,"white" if compact else role,points)
	for side in [-1,1]:
		var band := lerpf(3.1,2.3,axial)
		var stripe: float=side*(width+.001)
		g.box(parts,"blue",Vector3(-.85,stripe-.003,band),Vector3(.78,stripe+.003,band+.95))
		# The source side poses show less of the wing beyond the fuselage.
		var span := wing_span
		if not compact and side*(direction.x-direction.y)<0:
			span*=1-.25*maxf(0,-2*direction.x*direction.y)
		var wing := PackedVector3Array([Vector3(root,0,1.4),Vector3(sweep,side*span,1.2),
			Vector3(sweep-.11,side*span,1.2),Vector3(root-chord,0,1.4)])
		var first := parts.size()
		var wing_role := "white" if compact else "air_wing"
		g.slab(parts,wing_role,wing,.3)
		if not compact:
			for i in range(first+1,parts.size()): parts[i].role="air_edge"
			var root_offset := Vector3(0,0,.015)
			g.face(parts,"air_wing_root",PackedVector3Array([wing[0]+root_offset,
				wing[0].lerp(wing[1],.34)+root_offset,wing[3].lerp(wing[2],.34)+root_offset,wing[3]+root_offset]))
			var offset := Vector3(0,0,.025)
			g.face(parts,"air_leading",PackedVector3Array([wing[0]+offset,wing[1]+offset,
				wing[1].lerp(wing[2],.22)+offset,wing[0].lerp(wing[3],.08)+offset]))
		g.slab(parts,wing_role,PackedVector3Array([Vector3(-.67,0,2.5),Vector3(-.98,side*.48,2.3),
			Vector3(-1.10,side*.48,2.3),Vector3(-1.0,0,2.5)]),.25)
		if compact:
			g.box(parts,"metal",Vector3(-.25,side*.52-.06,-.3),Vector3(.10,side*.52+.06,1.5))
		else:
			var engine := Vector3(wing_shift-.13*detail,side*lerpf(.52,.54,detail),lerpf(.6,.15,detail))
			aircraft_engine(parts,engine,detail)
	# Two palette bands retain the original painted blue fin on a real surface.
	var fin_height := 9.5 if compact else lerpf(14.0,12.5,detail)
	var thickness := lerpf(.022,.035,detail)
	var lit_edge := signf(direction.x)*thickness
	var bands := 1 if compact else 2
	for side in [-1,1]:
		for band in bands:
			var low := float(band)/bands
			var high := float(band+1)/bands
			var role := "blue" if compact else ("air_tail_base" if band==0 else "air_tail_tip")
			g.face(parts,role,PackedVector3Array([
				Vector3(-1.02,side*thickness,lerpf(2,fin_height,low)),Vector3(-1.02,side*thickness,lerpf(2,fin_height,high)),
				Vector3(lerpf(-.67,-.89,high),side*thickness,lerpf(2,fin_height,high)),
				Vector3(lerpf(-.67,-.89,low),side*thickness,lerpf(2,fin_height,low))]))
	var fin := PackedVector3Array([Vector3(-1.02,0,2),Vector3(-1.02,0,fin_height),Vector3(-.89,0,fin_height),Vector3(-.67,0,2)])
	for edge in fin.size():
		var a: Vector3=fin[edge]
		var b: Vector3=fin[(edge+1)%fin.size()]
		if detail>.5:
			# The edge fills the native grid. Only its lit half carries blue paint.
			var lit := Vector3(0,lit_edge,0)
			var tint := "air_tail_tip" if direction.x>0 else "air_tail_base"
			g.face(parts,tint,PackedVector3Array([a,b,b+lit,a+lit]))
			g.face(parts,"air_side",PackedVector3Array([a-lit,b-lit,b,a]))
		else:
			var offset := Vector3(0,thickness,0)
			g.face(parts,"white" if compact else "air_leading",PackedVector3Array([a-offset,b-offset,b+offset,a+offset]))
	g.box(parts,"glass",Vector3(.88,-.065,2.8),Vector3(1.02,.065,3.35))
	for side in [-1,1]:
		var span := wing_span
		if not compact and side*(direction.x-direction.y)<0:
			span*=1-.25*maxf(0,-2*direction.x*direction.y)
		g.box(parts,"nav_red" if side<0 else "nav_white",Vector3(sweep-.13,side*span-.035,1.2),Vector3(sweep+.03,side*span+.035,2.2))


static func aircraft_engine(parts: Array, center: Vector3, axial: float) -> void:
	var g = NetworkModelGeometry
	var mouth := PackedVector3Array()
	# Wider underslung cowls stay round when their length is foreshortened.
	var width := lerpf(.06,.15,axial)
	var radius := lerpf(.9,1.75,axial)
	for segment in 8:
		var a := segment*TAU/8.0
		var b := (segment+1)*TAU/8.0
		var first := center+Vector3(0,cos(a)*width,sin(a)*radius)
		var last := center+Vector3(0,cos(b)*width,sin(b)*radius)
		g.face(parts,"air_engine" if segment<4 else "air_edge",PackedVector3Array([
			first+Vector3(-.25,0,0),first+Vector3(.10,0,0),last+Vector3(.10,0,0),last+Vector3(-.25,0,0)]))
		mouth.append(first+Vector3(.102,0,0))
	g.face(parts,"air_intake",mouth)


static func underground_height(city: CityState, world: Vector2) -> float:
	var tile := Vector2i((world+Vector2(.5,.5)).floor())
	var i := city.index_of(tile.x,tile.y)
	if i<0:
		return 0
	var local := world-Vector2(tile)
	var direction := (1 if local.x>=0 else 3) if absf(local.x)>absf(local.y) else (2 if local.y>=0 else 0)
	var shape := UndergroundModels.profile(city,i)
	var center := NetworkModelGeometry.surface_height(Vector2.ZERO,shape)-12
	var z := lerpf(center,shape[4+direction],maxf(absf(local.x),absf(local.y))*2)
	return city.land_altitude(tile.x,tile.y)+z/12.0


static func underground_commands(city: CityState, view: int) -> Array[CityDynamicCommand]:
	var result: Array[CityDynamicCommand]=[]
	for record in city.thing_count():
		var thing := city.thing(record)
		if thing==null or thing.type not in [12,13] or city.index_of(thing.x,thing.y)<0:
			continue
		var tile := city.underground[city.index_of(thing.x,thing.y)]
		if not (tile in range(1,16) or tile in [31,32,35]):
			continue
		if city.visible_altitude_levels<32 and underground_height(city,Vector2(thing.x,thing.y))>=city.visible_altitude_levels:
			continue
		var command := CityDynamicCommand.new()
		command.record=record
		command.sprite_id=view*500+374
		command.depth_order=(thing.x+thing.y)*city.map_size+thing.y
		command.train=true
		command.static_occlusion=false
		command.position=Vector2i(contact(city,Vector2(thing.x,thing.y)))/(4>>view)
		result.append(command)
	return result


static func subway_ports(city: CityState, tile: Vector2i) -> int:
	var i := city.index_of(tile.x,tile.y)
	if i<0:
		return 0
	var id := int(city.underground[i])
	if id in range(1,16):
		return UndergroundModels.PORTS[id-1]
	return {31:5,32:10,35:15}.get(id,0)


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
